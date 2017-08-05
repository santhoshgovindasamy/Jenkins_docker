FROM us.gcr.io/symphony-gce-dev/sym/alpine-oracle-java7-java8-maven-python27
MAINTAINER Hiep Nguyen <hiep.nguyen@symphony.com>

RUN apk update && apk add --no-cache git openssh-client curl unzip bash ttf-dejavu coreutils

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000
ARG http_port=8080
ARG agent_port=50000

ENV JENKINS_HOME /var/jenkins_home
ENV JENKINS_SLAVE_AGENT_PORT ${agent_port}

# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container, 
# ensure you use the same uid
RUN addgroup -g ${gid} ${group} \
    && adduser -h "$JENKINS_HOME" -u ${uid} -G ${group} -s /bin/bash -D ${user}

# Jenkins home directory is a volume, so configuration and build history 
# can be persisted and survive image upgrades
VOLUME /var/jenkins_home

# `/usr/share/jenkins/ref/` contains all reference configuration we want 
# to set on a fresh new installation. Use it to bundle additional plugins 
# or config file with your custom jenkins Docker image.
RUN mkdir -p /usr/share/jenkins/ref/init.groovy.d

ENV TINI_VERSION 0.14.0
ENV TINI_SHA 6c41ec7d33e857d4779f14d9c74924cab0c7973485d2972419a3b7c7620ff5fd

# Use tini as subreaper in Docker container to adopt zombie processes 
RUN curl -fsSL https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-static-amd64 -o /bin/tini && chmod +x /bin/tini \
  && echo "$TINI_SHA  /bin/tini" | sha256sum -c -

COPY init.groovy /usr/share/jenkins/ref/init.groovy.d/tcp-slave-agent-port.groovy
COPY createCredentials.groovy /usr/share/jenkins/ref/init.groovy.d/createCredentials.groovy
#COPY security.groovy /usr/share/jenkins/ref/init.groovy.d/security.groovy


# jenkins version being bundled in this docker image
ARG JENKINS_VERSION
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.60.1}

# jenkins.war checksum, download will be validated using it
ARG JENKINS_SHA=34fde424dde0e050738f5ad1e316d54f741c237bd380bd663a07f96147bb1390

# Can be used to customize where jenkins.war get downloaded from
ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war

# could use ADD but this one does not check Last-Modified header neither does it allow to control checksum 
# see https://github.com/docker/docker/issues/8331
RUN curl -fsSL ${JENKINS_URL} -o /usr/share/jenkins/jenkins.war \
  && echo "${JENKINS_SHA}  /usr/share/jenkins/jenkins.war" | sha256sum -c -

ENV JENKINS_UC https://updates.jenkins.io
RUN chown -R ${user} "$JENKINS_HOME" /usr/share/jenkins/ref /tmp  && \
    pip install diff_cover && \
    mkdir /opt/bin && \
    curl -o /opt/bin/cover2cover.py https://raw.githubusercontent.com/SymphonyOSF/cover2cover/master/cover2cover.py

# for main web interface:
EXPOSE ${http_port}

# will be used by attached slave agents:
EXPOSE ${agent_port}

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

USER ${user}

COPY jenkins-support /usr/local/bin/jenkins-support
COPY jenkins.sh /usr/local/bin/jenkins.sh
ENTRYPOINT ["/bin/tini", "--", "/usr/local/bin/jenkins.sh"]

# from a derived Dockerfile, can use `RUN plugins.sh active.txt` to setup /usr/share/jenkins/ref/plugins from a support bundle
COPY plugins.sh /usr/local/bin/plugins.sh
COPY install-plugins.sh /usr/local/bin/install-plugins.sh

# Update the plugin list here. It's IMPORTANT to specify both the plugin NAME and VERSION for VERSION CONTROL 
RUN /usr/local/bin/install-plugins.sh 	config-file-provider credentials ssh-credentials ssh-agent ssh-slaves  git-client git github github-api saml \
					github-oauth google-oauth-plugin kubernetes scm-api postbuild-task greenballs credentials-binding pipeline-utility-steps \
					workflow-aggregator github-organization-folder jira sonar matrix-project matrix-auth saferestart robot jobConfigHistory 

