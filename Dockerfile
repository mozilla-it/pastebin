FROM node:lts as staticfiles

ARG BUILD_EXTRAS=production

RUN echo "\nℹ️  Building staticfiles with "${BUILD_EXTRAS}" dependencies.\n"

WORKDIR /app

# Install the JS dependencies
COPY package.json package-lock.json Makefile ./

RUN if [ "$BUILD_EXTRAS" = "dev" ] ; then npm install --ignore-scripts ; else npm ci --ignore-scripts ; fi

# Copy the client/ directory and compile them. The Python application
# doesn't need to exist yet.
COPY client ./client

RUN mkdir -p dpaste/static
RUN make css
RUN make js

# ------------------------------------------------

FROM python:3.9.1 as build

ARG BUILD_EXTRAS=production
ARG DEBUG=False
ENV DEBUG=${DEBUG}
ENV PORT=8000

# add a non-privileged user for running the application
RUN groupadd --gid 10001 app && \
    useradd -g app --uid 10001 --shell /usr/sbin/nologin --create-home --home-dir /app app

RUN echo "\nℹ️  Building Django project with "${BUILD_EXTRAS}" dependencies.\n"

WORKDIR /app

# Upgrade pip, the Image one is quite old.
RUN pip install -U pip

# Copy the dpaste staticfiles to this image
COPY --from=staticfiles /app /app/

# Copy only the files necessary to install the dpaste project as an editable
# package. This improves caching.
COPY setup.py setup.cfg ./
COPY dpaste/__init__.py dpaste/
RUN pip install -e .[${BUILD_EXTRAS}]

# Copy the rest of the application code
COPY . .

USER app

# Collect all static files once.
RUN ./manage.py collectstatic --noinput

# By default run it with pyuwsgi, which is a great production ready
# server. For development, docker-compose will override it to use the
# regular Django runserver.
CMD ./manage.py migrate --noinput && ./manage.py pyuwsgi --http=:${PORT}

EXPOSE ${PORT}
