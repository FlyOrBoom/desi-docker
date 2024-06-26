### Docker image for analyzing AWS S3-hosted DESI data with Jupyterlab

# Build from container provided by Jupyter
# ========================================
# https://github.com/jupyter/docker-stacks
# We will be using scipy-notebook for the $STACK_BASE,
# but other options (such as minimal-notebook) are available.

ARG STACK_REGISTRY=quay.io
ARG STACK_OWNER=jupyter
ARG STACK_BASE=scipy-notebook
ARG STACK_VERSION=latest
FROM quay.io/jupyter/$STACK_BASE:$STACK_VERSION

# Set-up environment
# ==================

# Slight customization to Bash
# https://docs.docker.com/develop/develop-images/instructions/#using-pipes
# This fails commands even if errors occur before a pipe
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Work as root
USER root
WORKDIR /tmp

# Remove Jupyter stacks' default directory
RUN rm -r /home/jovyan

# Ensure all dependencies can be installed
RUN apt-get update --yes \
    && apt-get upgrade --yes \
    && apt-get clean

# Make directories
# ================
ENV HOME=/home

# Mountpoint mounts the S3 bucket to $DESI_DATA, with cache at $DESI_DATA_CACHE
ENV DESI_DATA=$HOME/desidata
ENV DESI_DATA_CACHE=$HOME/.desidata_cache

# Some NERSC tutorials use this hard-coded path instead, which we symlink
ENV DESI_NERSC=/global/cfs/cdirs/desi
ENV DESI_DATA_NERSC=$DESI_NERSC/public

# NERSC also provides a "scratch" directory for scratch work
ENV SCRATCH=$HOME/scratch

# Docker mounts local user files in $(pwd) to $SYNCED,
ENV SYNCED=$HOME/synced

# DESI Python packages are cloned to $DESI_HUB
ENV DESI_HUB=$HOME/desihub

# Create directories
RUN mkdir -p $HOME $DESI_HUB $DESI_DATA $DESI_DATA_CACHE $DESI_NERSC $SCRATCH $SYNCED \
    && ln -s $DESI_DATA $DESI_DATA_NERSC

# Add startup file to home directory
COPY ./welcome.ipynb $HOME

# Install AWS Mountpoint
# ======================
# https://docs.aws.amazon.com/AmazonS3/latest/userguide/mountpoint-installation.html
# Installs to /usr/bin/mountpoint.
# $(uname -i) returns the device hardware platform architecture,
# e.g. x86_64, amd64, required for downloading the right executables

RUN wget "https://s3.amazonaws.com/mountpoint-s3-release/latest/$(uname -i)/mount-s3.deb" -O ./mount-s3.deb \
    && apt-get install --yes --no-install-recommends ./mount-s3.deb \
    && apt-get clean \
    && rm ./mount-s3.deb

# Install DESI Python dependencies with Mamba and pip
# ===================================================
# https://desi.lbl.gov/trac/wiki/Pipeline/GettingStarted/Laptop
# Installing big libraries one-by-one to avoid memory issues

ENV CONDA_PACKAGES="numpy scipy astropy pyyaml requests ipython jupyter-resource-usage h5py scikit-learn matplotlib-base numba sqlalchemy pytz sphinx seaborn fitsio"
RUN for package in $CONDA_PACKAGES; do \
    mamba install -c conda-forge --yes $package; done \
    && mamba clean --all -f --yes \
    && pip install healpy speclite

# Install DESI Python libraries
# =============================
# https://github.com/desihub

ARG DESI_PACKAGES="desiutil specter specsim desitarget desispec desisim desimodel redrock redrock-templates desisurvey surveysim"
RUN for package in $DESI_PACKAGES; do \
    git clone --depth 1 \
        https://github.com/desihub/$package.git \
        $DESI_HUB/$package; done

# Clone tutorials
RUN git clone --depth 1 \
        https://github.com/desihub/tutorials.git \
        $HOME/tutorials

# Runtime script
# ==============

COPY ./run.sh /usr/local/bin
RUN chmod +x /usr/local/bin/run.sh
ENTRYPOINT /usr/local/bin/run.sh

# Return to user privileges
# =========================

RUN fix-permissions $HOME
RUN fix-permissions $DESI_NERSC
USER $NB_UID
WORKDIR $HOME

