#!/usr/bin/env python
# coding=utf-8
import logging
from multiprocessing import Process
from database import NodeModel, GatewayModel
import psycopg2
import memcache
import json

class ForwardProcess(Process):
    def __init__(self, zmq_sock, db_host, db_port, db_user, db_pwd, ns_id, memcached_list):
        super(ForwardProcess, self).__init__()
        try:
            self.conn = psycopg2.connect(database='lora', user=db_user, password=db_pwd, host=db_host, port=db_port)   
            self.db = self.conn.cursor(cursor_factory = psycopg2.extras.RealDictCursor)

            self.mc = memcache.Client(memcached_list) 

            self.node_model = NodeModel(self.db, self.mc) 
            self.gateway_model = GatewayModel(self.db, self.mc) 
        except Exception, e:
            logging.error(e)
            raise ValueError

    def run(self):
        while True:
            try:
                for message in self.kafka_conn:
                    print message
                    #TODO need define downlink packet format
            except Exception, e:
                logging.error('Error in forward msg to gateway: %s' % str(e))
                pass

