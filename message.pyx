#!/usr/bin/env python
# coding=utf-8

import logging
import struct
import json
import binascii
import base64
import array
import socket

HEADER_LEN = 4

LORA_FULL_ADDRESS_LEN = 8
LORA_SHORT_ADDRESS_LEN = 4

class GatewayMessage():
    def __init__(self, data, length):
        if length < HEADER_LEN:
            raise ValueError
   
        version = data[0] 
        if version != 1:
            raise ValueError
        else:
            self.__dict__.update({'version': version})

        token = data[1] << 8 | data[2] 
        self.__dict__.update({'token': token})

        msg_type = data[3]
        self.__dict__.update({'type': msg_type})

        if length > HEADER_LEN + LORA_FULL_ADDRESS_LEN:
            self.__dict__.update({'gw_mac': data[HEADER_LEN: HEADER_LEN + LORA_FULL_ADDRESS_LEN]})
            self.__dict__.update({'payload': data[HEADER_LEN + LORA_FULL_ADDRESS_LEN: length]})
            self.__dict__.update({'payload_len': length - HEADER_LEN - LORA_FULL_ADDRESS_LEN})
        else:
            self.__dict__.update({'gw_mac': None})
            self.__dict__.update({'payload': None})
            self.__dict__.update({'payload_len': 0})

class GatewayData():
    def __init__(self, data):
        try:
            payload = data.decode("utf-8") 
            payload_json = json.loads(payload)
            self.__dict__.update(payload_json)
        except Exception, e:
            logging.error('GatewayData error:' % str(e))
            raise ValueError

class NodeData():
    def __init__(self, raw_data):
        try:
            data = binascii.b2a_hex(binascii.a2b_base64(raw_data))
            self.__dict__.update({'data': data[:-4]})# exclude mic
 
            data = map(ord, data.decode('hex'))
            self.__dict__.update({'bin_data': data[:-4]})# exclude mic
            
            self.__dict__.update({'len': len(data) - 4})#exclude mic

            header = data[:8]
                
            frame_type = header[0] & 0xe0 >> 5
            self.__dict__.update({'frame_type': frame_type})

            version = header[0] & 0x03
            self.__dict__.update({'version': version})

            #address = header[1:5]
            #ntohl
            address = [header[2], header[1], header[4], header[3]]
            self.__dict__.update({'address': address})

            adr_enabled = header[5] & 0x80
            if adr_enabled:
                self.__dict__.update({'adr_enabled': True})
            else:
                self.__dict__.update({'adr_enabled': False})

            resp_need = header[5] & 0x40
            if resp_need:
                self.__dict__.update({'resp_need': True})
            else:
                self.__dict__.update({'resp_need': False})
            
            ack = header[5] & 0x20
            if ack:
                self.__dict__.update({'ack': True})
            else:
                self.__dict__.update({'ack': False})

            seq = (header[7] << 8) + header[6]
            self.__dict__.update({'seq': seq})

            min_header_len = 8
            self.__dict__.update({'min_header_len': min_header_len})

            option_len = header[5] & 0x0F 
            self.__dict__.update({'option_len': option_len})

            if option_len > 0:
                option = data[min_header_len: min_header_len + option_len - 1]
                self.__dict__.update({'option': option})
            else:
                self.__dict__.update({'option': []})
     
            port = data[min_header_len + option_len]
            self.__dict__.update({'port': port})

            payload = data[min_header_len + option_len: -4]
            self.__dict__.update({'payload': payload})

            payload_len = len(payload)
            self.__dict__.update({'payload_len': payload_len})

            mic = data[-4:]
            self.__dict__.update({'mic': mic})
        except Exception, e:
            logging.error(e)
            raise ValueError

 
