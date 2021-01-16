FROM postgis/postgis:13-3.1

LABEL maintainer="PgOSM-Flex - https://github.com/rustprooflabs/pgosm-flex"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        sqitch wget ca-certificates \
        git make cmake g++ \
	    libboost-dev libboost-system-dev \
	    libboost-filesystem-dev libexpat1-dev zlib1g-dev \
	    libbz2-dev libpq-dev libproj-dev lua5.2 liblua5.2-dev \
	    lua-dkjson \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /tmp
RUN git clone git://github.com/openstreetmap/osm2pgsql.git \
	&& mkdir osm2pgsql/build \
	&& cd osm2pgsql/build \
	&& cmake .. \
	&& make \
	&& make install \
	&& apt remove -y \
		git make cmake g++ \
	    libboost-dev libboost-system-dev \
	    libboost-filesystem-dev libexpat1-dev zlib1g-dev \
	    libbz2-dev libpq-dev libproj-dev \
	&& apt autoremove -y \
	&& cd /tmp && rm -r /tmp/osm2pgsql


WORKDIR /app
COPY . ./
