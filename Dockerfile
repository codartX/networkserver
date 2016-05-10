FROM ubuntu:14.04

# make sure the package repository is up to date
RUN apt-get update

RUN apt-get install -y python-pip

RUN pip install pyzmq-static

RUN mkdir -p /opt/networkserver

ADD *.so networkserver /opt/networkserver

WORKDIR /opt/networkserver
