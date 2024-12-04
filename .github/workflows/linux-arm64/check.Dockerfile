ARG PYTHON_VERSION=3.8


FROM python:$PYTHON_VERSION AS build

ADD *.whl .

RUN pip3 install --find-links . --pre lincs

RUN lincs --version >/output.txt
RUN lincs --help >>/output.txt
