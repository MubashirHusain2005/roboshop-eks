FROM mysql:5.7


ENV MYSQL_ROOT_PASSWORD=rootpass \
    MYSQL_DATABASE=cities \
    MYSQL_USER=shipping \
    MYSQL_PASSWORD=secret
    

COPY scripts/ /docker-entrypoint-initdb.d/


RUN chmod +x /docker-entrypoint-initdb.d/*.sh || true \
    && sed -i 's/\r$//' /docker-entrypoint-initdb.d/*.sh || true

EXPOSE 3306

#
