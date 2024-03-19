# Custom EBRICK Docker image

# Copyright (c) 2024 Zero ASIC Corporation
# This code is licensed under Apache License 2.0 (see LICENSE for details)

# To rebuild this image and push it to ghcr.io, run:
#
# docker build -t ghcr.io/OWNER/IMAGE_NAME:TAG .
# docker login ghcr.io
# docker push ghcr.io/OWNER/IMAGE_NAME:TAG
#
# where OWNER is your GitHub username or organization,
# IMAGE_NAME is the name that you want to publish the
# image under (e.g., "ebrick_demo"), and TAG is the tag
# you want to associate with the build (e.g., "latest").

FROM ghcr.io/siliconcompiler/sc_tools:latest

# add project-specific tools below

# install RISC-V toolchain.  the final remove in the same RUN command
# is important to keep the docker image size low (particularly true
# for this package, where the build consumes several GB)
# https://github.com/riscv-collab/riscv-gnu-toolchain
RUN \
apt update -y && \
apt install -y autoconf automake autotools-dev curl python3 \
    libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex \
    texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev ninja-build && \
git clone https://github.com/riscv/riscv-gnu-toolchain && \
cd riscv-gnu-toolchain && \
git pull && \
git checkout 2023.01.04 && \
./configure --prefix=/opt/riscv && \
make -j `nproc` && \
cd .. && \
rm -rf riscv-gnu-toolchain && \
apt clean && \
rm -rf /var/lib/apt/lists/*

# update environment variable to include RISC-V tools
ENV PATH=$PATH:/opt/riscv/bin
