FROM ubuntu:20.04

ARG lincs_version

WORKDIR /wd

ADD *.tar.gz .

RUN find . && false
