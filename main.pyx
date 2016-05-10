#!/usr/bin/env python
# coding=utf-8
import logging
import sys,os, signal, getopt
import socket
import json
import zmq
import time
from parser import MsgParserProcess
import multiprocessing
from forward import ForwardProcess
from pkt_rx import RxProcess


def main():
    try:
        f = open('config.json', 'r')
        raw_data = f.read()
        config_json = json.loads(raw_data)
    except Exception, e:
        print 'Wrong format config file, ', e
        sys.exit()

    if not 'database_cfg' in config_json or not 'mc_list' in config_json or not 'process_num' in config_json or not 'local_port' in config_json or not 'zmq_port' in config_json:
        print 'Config file invalid'
        sys.exit()

    context = zmq.Context()
    socket = context.socket(zmq.PUB)
    socket.bind('tcp://*:%d' % (config_json['zmq_port']))
    msg_queue = multiprocessing.Queue()
    process_pool = []

    try:
        for i in range(int(config_json['process_num'])):
            p = MsgParserProcess(socket, 
                                 config_json['database_cfg']['host'],
                                 config_json['database_cfg']['port'], 
                                 config_json['database_cfg']['username'], 
                                 config_json['database_cfg']['password'],
                                 config_json['mc_list'], msg_queue)
            p.daemon = True
            process_pool.append(p)
            p.start()
        
        p.daemon = True
        p.start()
        
        p = RxProcess('0.0.0.0', config_json['local_port'], msg_queue)
        p.daemon = True
        p.start()

    except Exception, e:
        print 'Process create fail,', e
        sys.exit()

    for process in process_pool:
        process.join()

    p.join()
    msg_queue.close()

if __name__ == "__main__":
    #logging.basicConfig(
    #    format='%(asctime)s.%(msecs)s:%(name)s:%(thread)d:%(levelname)s:%(process)d:%(message)s',
    #    level=logging.DEBUG
    #    )
    main()

