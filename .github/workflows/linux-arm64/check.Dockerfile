ARG PYTHON_VERSION=3.8


FROM python:$PYTHON_VERSION AS build

ADD *.whl .

RUN pip3 install --find-links . --pre lincs

RUN lincs --version >/output.txt
RUN lincs --help >>/output.txt
RUN lincs generate classification-problem 3 2 | tee problem.yml >>/output.txt
RUN lincs generate classification-model problem.yml | tee model.yml >>/output.txt
RUN lincs generate classified-alternatives problem.yml model.yml 100 >>/output.txt
