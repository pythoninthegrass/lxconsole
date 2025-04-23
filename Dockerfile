# syntax=docker/dockerfile:1.7.1

ARG PYTHON_VERSION=3.10.17

FROM python:${PYTHON_VERSION} as builder

ARG DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get -qq update \
    && apt-get -qq install --no-install-recommends -y \
    ca-certificates \
    build-essential \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# venv
ARG UV_PROJECT_ENVIRONMENT="/opt/venv"
ENV VENV="${UV_PROJECT_ENVIRONMENT}"
ENV PATH="$VENV/bin:$PATH"

# uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

COPY pyproject.toml .

# optimize startup time, don't use hardlinks, set cache for buildkit mount,
# set uv timeout
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy
ENV UV_CACHE_DIR=/opt/uv-cache/
ENV UV_HTTP_TIMEOUT=90

RUN --mount=type=cache,target=/opt/uv-cache,sharing=locked \
    uv venv $UV_PROJECT_ENVIRONMENT \
    && uv pip install -r pyproject.toml

FROM python:${PYTHON_VERSION}-slim as deps

ARG DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get -qq update \
    && apt-get -qq install --no-install-recommends -y \
    ca-certificates \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

FROM deps as runner

# standardise on locale, don't generate .pyc, enable tracebacks on seg faults
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONFAULTHANDLER 1

ARG USER_NAME=lxconsole
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USER_NAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USER_NAME

WORKDIR /opt/lxconsole

ARG VENV="/opt/venv"
ENV PATH=$VENV/bin:$PATH

# Copy the venv from the builder stage
COPY --from=builder $VENV $VENV

# Copy application code
COPY --chown=$USER_NAME:$USER_NAME lxconsole /opt/lxconsole/lxconsole
COPY --chown=$USER_NAME:$USER_NAME run.py /opt/lxconsole/run.py

RUN chown -R $USER_NAME:$USER_NAME /opt/lxconsole

USER $USER_NAME

EXPOSE 5000

ENTRYPOINT ["gunicorn"]
CMD ["--bind", "0.0.0.0:5000", "run:app"]
