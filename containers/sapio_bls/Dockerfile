# Sapio Platform version to use
ARG SAPIO_PLATFORM_VERISON="2025.10.06.2015-1148-yqiao_eksneeds"

FROM ubuntu:22.04 AS addons


RUN apt-get update
RUN apt-get install unzip

RUN mkdir -p /opt/sapiosciences/velox_server/addons/


COPY files/foundations.jar /opt/sapiosciences/velox_server/addons/foundations.jar
COPY files/analytics.jar /opt/sapiosciences/velox_server/addons/analytics.jar
COPY customization?.jar /opt/sapiosciences/velox_server/addons/customizations.jar

WORKDIR /opt/sapiosciences/velox_server/addons/
RUN unzip -o analytics.jar "*lib/*" "plugins/*" "wars/*"
RUN unzip -o foundations.jar "*lib/*" "plugins/*" "wars/*"
RUN if test -f customizations.jar; then  \
    echo "customizations.jar found. Extracting...";  \
    RUN unzip -o customizations.jar "*lib/*" "plugins/*" "wars/*"; \
    echo "customizations.jar extracted successfully.";  \
    else echo "customizations.jar not found";  \
    fi

RUN mv wars clientplugins;
RUN mv applib sharedlib

RUN chown -R 1000:1000 /opt/sapiosciences/velox_server/addons

RUN rm /opt/sapiosciences/velox_server/addons/*.jar

WORKDIR /opt/sapiosciences/velox_server/addons/clientplugins
RUN find . -name "*.war" | while read filename; do unzip -o -d "`basename -s .war "$filename"`" "$filename"; done;
RUN rm *.war


COPY files/systemdevtools.jar /opt/sapiosciences/velox_server/addons/plugins/


FROM 659459510985.dkr.ecr.us-east-1.amazonaws.com/sapiosciences/sapio_platform/platform_default:$SAPIO_PLATFORM_VERISON
COPY --from=addons /opt/sapiosciences/velox_server/addons/ /opt/sapiosciences/velox_server/addons/


WORKDIR /opt/sapiosciences/velox_server
CMD ["/opt/sapiosciences/velox_server/launch.sh"]

# FR-52114 Set entrypoint to s6 so we can launch multiple services
ENTRYPOINT ["/init"]