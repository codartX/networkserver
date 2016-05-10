#!/usr/bin/env python
# coding=utf-8
import psycopg2.extras
import json

class GatewayModel():
    def __init__(self, db, mc):
        self.db = db
        self.mc = mc


class NodeModel():
    def __init__(self, db, mc):
        self.db = db
        self.mc = mc

    def get_node_by_addr(self, node_addr):
        node = self.mc.get(node_addr)
        if node:
           return json.loads(node)
        else:
           sql = """SELECT * FROM "at_lora_nodes" WHERE dev_addr = '%s';""" % node_addr 
           self.db.execute(sql)
           node = self.db.fetchone()
           if node is not None:
               self.mc.set(node_addr, json.dumps(node))
               return json.loads(node)
           else:
               return None
        
    def get_node_app_id(self, node_addr):
        node = self.get_node_by_addr(node_addr)
        if 'app_server_id' in node:
            return node['app_server_id']
        else:
            return None

    def get_node_best_gw(self, node_addr):
        node = self.get_node_by_addr(node_addr)
        if 'gw' in node:
            return node['gw']
        else:
            return None

    def set_node_best_gw(self, node_addr, gw_id, gw_addr, rssi):
        node = self.get_node_by_addr(node_addr)
        node['gw'] = {'id': gw_id, 'address': gw_addr, 'rssi': rssi}
        self.mc.set(node_addr, json.dumps(node)) 

    def get_node_auth_key(self, node_addr):
        node = self.get_node_by_addr(node_addr)
        if 'authen_key' in node:
            return node['authen_key']
        else:
            return None

    #def update_node_stats(self, node_addr, stats):
        

