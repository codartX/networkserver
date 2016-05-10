#!/usr/bin/env python
# coding=utf-8
import logging
import os, sys
from multiprocessing import Process, Queue
from kafka.client import KafkaClient
from kafka.producer import SimpleProducer
import psycopg2
import binascii
import json
import memcache
import psycopg2.extras
from Crypto.Cipher import AES
from Crypto.Hash import CMAC
from database import NodeModel, GatewayModel
from message import GatewayMessage, GatewayData, NodeData   
import time

LORA_VERSION_1 = 1

PUSH_DATA = 0
PUSH_ACK  = 1
PULL_DATA = 2
PULL_RESP = 3
PULL_ACK  = 4

default_key = [0x2B, 0x7E, 0x15, 0x16, 0x28, 0xAE, 0xD2, 0xA6, 0xAB, 0xF7, 0x15, 0x88, 0x09, 0xCF, 0x4F, 0x3C]

current_milli_time = lambda: int(round(time.time() * 1000))

class MsgParserProcess(Process):
    def __init__(self, kafka_addr, kafka_port, db_host, db_port, db_user, db_pwd, memcached_list, msg_queue):
        super(MsgParserProcess, self).__init__()
        self.queue = msg_queue
        try:
            self.client = KafkaClient(str(kafka_addr) + ':' + str(kafka_port))
            self.kafka_conn = SimpleProducer(self.client)

            self.conn = psycopg2.connect(database='lora', user=db_user, password=db_pwd, host=db_host, port=db_port)   
            self.db = self.conn.cursor(cursor_factory = psycopg2.extras.RealDictCursor)

            self.mc = memcache.Client(memcached_list) 

            self.node_model = NodeModel(self.db, self.mc) 
            self.gateway_model = GatewayModel(self.db, self.mc) 
        except Exception, e:
            logging.error(e)
            raise ValueError

        self.process_func = {
            PUSH_DATA: self.push_data_process,
            PUSH_ACK:  self.push_ack_process,
            PULL_DATA: self.pull_data_process,
            PULL_RESP: self.pull_resp_process,
            PULL_ACK:  self.pull_ack_process,
        }

    def generate_mic(self, data, data_len, address, up, seq):
        mic = []
        b = []
        b.append(0x49) #authentication flags
        b.extend([0, 0, 0, 0])
        if up:
            b.append(0)
        else:
            b.append(1)
        b.extend([address[1], address[0], address[3], address[2]])
        b.extend([seq & 0xFF, seq >> 8 & 0xFF, seq >> 16 & 0xFF, seq >> 24 & 0xFF])
        b.extend([0, data_len])

        auth_key = self.node_model.get_node_auth_key(binascii.hexlify(bytearray(address)))
        if not auth_key:
            secret = default_key
        else:
            secret = auth_key
 
        #just for test
        secret = "".join(map(chr, default_key))
        cobj = CMAC.new(secret, ciphermod=AES)
        cobj.update("".join(map(chr, b)))
        cobj.update("".join(map(chr, data)))
        mic = cobj.hexdigest()[:8]
        return mic

    def send_ack(self, sock, from_addr, recv_msg, msg_type):
        data = []
        data.append(LORA_VERSION_1) 
        data.append(recv_msg.token >> 8 & 0xFF)
        data.append(recv_msg.token & 0xFF) 
        data.append(msg_type)
        sock.send(binascii.hexlify(bytearray(data)))

    def push_data_process(self, sock, from_addr, msg):
        try:
            gw_data = GatewayData(msg.payload) 
        except Exception, e:
            logging.error('Parse gateway data error:' % str(e))
            return
            
        if 'rxpk' in gw_data.__dict__:
            #check gw data, like rssi, snr, etc..

            try: 
                node_data = NodeData(gw_data.rxpk[0]['data'])
            except Exception, e:
                logging.error(e)
                return

            dev_addr = binascii.hexlify(bytearray(node_data.address))
            node = self.node_model.get_node_by_addr(dev_addr) 
            if not node:
                logging.error('Node do not exist')
                return

            #TODO: check mic etc..
            mic = self.generate_mic(node_data.bin_data, node_data.len, node_data.address, True, node_data.seq)
            if mic != binascii.hexlify(bytearray(node_data.mic)):
                logging.error('MIC mismatch')
                return

            try:
                gw = self.node_model.get_node_best_gw(dev_addr) 
                if gw and gw['rssi'] < gw_data.rxpk[0]['rssi'] or not gw:
                    self.node_model.set_node_best_gw(dev_addr, binascii.hexlify(bytearray(msg.gw_mac)), from_addr, gw_data.rxpk[0]['rssi'])
            except Exception, e:
                logging.error(e)
                return
            
            app_id = self.node_model.get_node_app_id(dev_addr) 
            if app_id:
                self.kafka_conn.send_messages(app_id, msg.payload)
            else:
                logging.error('App ID does not exist')
                return

        elif 'stat' in gw_data.__dict__:
            return
        elif 'command' in gw_data.__dict__:
            return
        else:
            return

        #don't forget ack
        self.send_ack(sock, from_addr, msg, PUSH_ACK)
 
    def push_ack_process(self, sock, from_addr, msg):
        return

    def pull_data_process(self, sock, from_addr, msg):
        #don't forget ack
        self.send_ack(sock, from_addr, msg, PULL_ACK)
        return

    def pull_resp_process(self, sock, from_addr, msg):
        return

    def pull_ack_process(self, sock, from_addr, msg):
        return

    def process_data(self, sock, from_addr, data, length):
        try:
            msg = GatewayMessage(data, length)
        except Exception, e:
            logging.error('Gateway message parse fail:%s' % str(e))
            return

        if msg.payload:
            try:
                self.process_func[msg.type](sock, from_addr, msg) 
            except Exception, e:
                logging.error('Process data error:%s' % str(e))
                return

    def run(self):
        while True:
            msg = self.queue.get()
            data = msg['data']
            from_addr = msg['addr']
            length = msg['len']
            sock = msg['sock']

            #process data
            try:
                self.process_data(sock, from_addr, data, length)
            except Exception, e:
                logging.error('Error in process_data: %s' % str(e))
                pass

