#!/usr/bin/env python
# coding=utf-8
import logging
import socket
import SocketServer
from multiprocessing import Process

class TCPHandler(SocketServer.BaseRequestHandler):
    def handle(self):
        # self.request is the TCP socket connected to the client
        buf = bytearray(512)
        length = self.request.recv_into(buf)
        try:
            self.server.msg_queue.put({'addr':self.client_address[0], 'data':buf, 'len': length, 'sock': self.request})
        except Exception, e:
            logging.error('Enqueue fail,error:' % str(e))
            self.server.msg_queue.close()
            self.server.shutdown()

class RxProcess(Process):
    def __init__(self, ip, port, msg_queue):
        super(RxProcess, self).__init__()
        self.ip = ip
        self.port =port
        self.msg_queue = msg_queue

    def run(self):
        try:
            self.server = SocketServer.TCPServer((self.ip, self.port), TCPHandler)
            self.server.socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 32*1024*1024)
            self.server.msg_queue = self.msg_queue
            self.server.serve_forever()    
        except Exception, e:
            logging.error(e)
            self.msg_queue.close()
            return
