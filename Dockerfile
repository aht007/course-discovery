FROM ubuntu:focal as app

# System requirements.
RUN apt update && \
  apt-get install -qy \ 
  curl \
  vim \
  git-core \
  language-pack-en \
  build-essential \
  python3.8-dev \
  python3-virtualenv \
  python3.8-distutils \
  libmysqlclient-dev \
  libssl-dev \
  libcairo2-dev && \
  rm -rf /var/lib/apt/lists/*

# Use UTF-8.
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

ARG COMMON_APP_DIR="/edx/app"
ARG DISCOVERY_SERVICE_NAME="discovery"
ENV DISCOVERY_HOME "${COMMON_APP_DIR}/${DISCOVERY_SERVICE_NAME}"
ARG DISCOVERY_APP_DIR="${COMMON_APP_DIR}/${DISCOVERY_SERVICE_NAME}"
ARG SUPERVISOR_APP_DIR="${COMMON_APP_DIR}/supervisor"
ARG DISCOVERY_VENV_DIR="${COMMON_APP_DIR}/${DISCOVERY_SERVICE_NAME}/venvs/${DISCOVERY_SERVICE_NAME}"
ARG SUPERVISOR_VENVS_DIR="${SUPERVISOR_APP_DIR}/venvs"
ARG SUPERVISOR_VENV_DIR="${SUPERVISOR_VENVS_DIR}/supervisor"
ARG DISCOVERY_CODE_DIR="${DISCOVERY_APP_DIR}/${DISCOVERY_SERVICE_NAME}"
ARG DISCOVERY_NODEENV_DIR="${COMMON_APP_DIR}/${DISCOVERY_SERVICE_NAME}/nodeenvs/${DISCOVERY_SERVICE_NAME}"
ARG SUPERVISOR_AVAILABLE_DIR="${COMMON_APP_DIR}/supervisor/conf.available.d"
ARG SUPERVISOR_VENV_BIN="${SUPERVISOR_VENV_DIR}/bin"
ARG SUPEVISOR_CTL="${SUPERVISOR_VENV_BIN}/supervisorctl"
ARG SUPERVISOR_VERSION="4.2.1"
ARG SUPERVISOR_CFG_DIR="${SUPERVISOR_APP_DIR}/conf.d"
ARG DISCOVERY_NODE_VERSION="16.14.0"
ARG DISCOVERY_NPM_VERSION="8.5.x"

# These variables were defined in Ansible configuration but I couldn't find them being used anywhere.
# I have commented these out for now but I would like to take opinion from someone having more knowledge about them
# and whether it is safe to comment them out. I did basic smoke testing and everything seems to be working fine.

# ENV DISCOVERY_ECOMMERCE_API_URL 'https://localhost:8002/api/v2/'
# ENV DISCOVERY_COURSES_API_URL '${DISCOVERY_LMS_ROOT_URL}/api/courses/v1/'
# ENV DISCOVERY_ORGANIZATIONS_API_URL '${DISCOVERY_LMS_ROOT_URL}/api/organizations/v0/'
# ENV DISCOVERY_MARKETING_API_URL 'https://example.org/api/catalog/v2/'
# ENV DISCOVERY_MARKETING_URL_ROOT 'https://example.org/'


ENV HOME /root
ENV PATH "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
ENV PATH "${DISCOVERY_VENV_DIR}/bin:${DISCOVERY_NODEENV_DIR}/bin:$PATH"
ENV COMMON_CFG_DIR "/edx/etc"
ENV DISCOVERY_CFG_DIR "${COMMON_CFG_DIR}/discovery"
ENV DISCOVERY_CFG "/edx/etc/discovery.yml"

ENV DISCOVERY_NODEENV_DIR "${DISCOVERY_HOME}/nodeenvs/${DISCOVERY_SERVICE_NAME}"
ENV DISCOVERY_NODEENV_BIN "${DISCOVERY_NODEENV_DIR}/bin"
ENV DISCOVERY_NODE_MODULES_DIR "${DISCOVERY_CODE_DIR}}/node_modules"
ENV DISCOVERY_NODE_BIN "${DISCOVERY_NODE_MODULES_DIR}/.bin"

RUN addgroup discovery
RUN adduser --disabled-login --disabled-password discovery --ingroup discovery

# Make necessary directories and environment variables.
RUN mkdir -p /edx/var/discovery/staticfiles
RUN mkdir -p /edx/var/discovery/media
# Log dir
RUN mkdir /edx/var/log/

RUN virtualenv -p python3.8 --always-copy ${DISCOVERY_VENV_DIR}
RUN virtualenv -p python3.8 --always-copy ${SUPERVISOR_VENV_DIR}

# No need to activate discovery venv as it is already in path
RUN pip install nodeenv

#install supervisor and deps in its virtualenv
RUN . ${SUPERVISOR_VENV_BIN}/activate && \
  pip install supervisor==${SUPERVISOR_VERSION} backoff==1.4.3 boto==2.48.0 && \
  deactivate

RUN nodeenv ${DISCOVERY_NODEENV_DIR} --node=${DISCOVERY_NODE_VERSION} --prebuilt
RUN npm install -g npm@${DISCOVERY_NPM_VERSION}

COPY requirements/production.txt ${DISCOVERY_CODE_DIR}/requirements/production.txt

RUN pip install -r ${DISCOVERY_CODE_DIR}/requirements/production.txt

# Working directory will be root of repo.
WORKDIR ${DISCOVERY_CODE_DIR}

# Copy just JS requirements and install them.
COPY package.json package.json
COPY package-lock.json package-lock.json
RUN npm install --production
COPY bower.json bower.json
RUN ./node_modules/.bin/bower install --allow-root --production

# Copy over rest of code.
# We do this AFTER requirements so that the requirements cache isn't busted
# every time any bit of code is changed.
COPY . .
COPY /configuration_files/discovery_gunicorn.py ${DISCOVERY_HOME}/discovery_gunicorn.py
# deleted this file completely and defined the env variables in dockerfile's respective target images.
# COPY configuration_files/discovery_env ${DISCOVERY_HOME}/discovery_env
COPY /configuration_files/discovery-workers.sh ${DISCOVERY_HOME}/discovery-workers.sh
COPY /configuration_files/discovery.yml ${DISCOVERY_CFG}
COPY /scripts/discovery.sh ${DISCOVERY_HOME}/discovery.sh
# create supervisor job
COPY /configuration_files/supervisor.service /etc/systemd/system/supervisor.service
COPY /configuration_files/supervisor.conf ${SUPERVISOR_CFG_DIR}/supervisor.conf
COPY /configuration_files/supervisorctl ${SUPERVISOR_VENV_BIN}/supervisorctl
# Manage.py symlink
COPY /manage.py /edx/bin/manage.discovery

# Expose canonical Discovery port
EXPOSE 18381

FROM app as prod

ENV DJANGO_SETTINGS_MODULE "course_discovery.settings.production"

RUN make static

ENTRYPOINT ["/edx/app/discovery/discovery.sh"]

FROM app as dev

ENV DJANGO_SETTINGS_MODULE "course_discovery.settings.devstack"

RUN pip install -r ${DISCOVERY_CODE_DIR}/requirements/local.txt

COPY /scripts/devstack.sh ${DISCOVERY_HOME}/devstack.sh

RUN chown discovery:discovery /edx/app/discovery/devstack.sh && chmod a+x /edx/app/discovery/devstack.sh

# Devstack related step for backwards compatibility
RUN touch /edx/app/${DISCOVERY_SERVICE_NAME}/${DISCOVERY_SERVICE_NAME}_env

ENTRYPOINT ["/edx/app/discovery/devstack.sh"]
CMD ["start"]
