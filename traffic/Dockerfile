# python:3.12-slim rather than locustio/locust: the official Locust image has no
# usable amd64 variant in this build environment, and the demo has to be
# buildable from an Apple Silicon laptop for amd64 GKE nodes.
FROM python:3.12-slim

RUN pip install --no-cache-dir locust==2.32.4

WORKDIR /home/locust
COPY locustfile.py /home/locust/
COPY scenario-templates/ /home/locust/scenario-templates/

ENTRYPOINT ["locust"]
