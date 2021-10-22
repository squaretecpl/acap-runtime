# Dockerfile for acap-runtime on camera
ARG UBUNTU_VERSION=20.04
ARG BASE_IMAGE=axisecp/acap-api:4.0-armv7hf-ubuntu$UBUNTU_VERSION

FROM $BASE_IMAGE as api
LABEL maintainer="rapid@axis.com"

## Build environment
ENV CC="arm-linux-gnueabihf-gcc -mthumb -mfpu=neon -mfloat-abi=hard -mcpu=cortex-a9"
ENV CXX="arm-linux-gnueabihf-g++ -mthumb -mfpu=neon -mfloat-abi=hard -mcpu=cortex-a9"
ENV CPP="arm-linux-gnueabihf-gcc -E -mthumb -mfpu=neon -mfloat-abi=hard -mcpu=cortex-a9"
ENV LIB=/usr/lib/arm-linux-gnueabihf
ENV PKG_CONFIG_LIBDIR=$PKG_CONFIG_LIBDIR:$LIB/pkgconfig
ENV DEBIAN_FRONTEND=noninteractive
ENV SYSROOT=/opt/axis/sdk/temp/sysroots/armv7hf/usr

# Add source for target arch
RUN echo \
"deb [arch=amd64] http://us.archive.ubuntu.com/ubuntu/ focal main restricted universe multiverse\n\
deb [arch=amd64] http://us.archive.ubuntu.com/ubuntu/ focal-updates main restricted universe multiverse\n\
deb [arch=amd64] http://us.archive.ubuntu.com/ubuntu/ focal-backports main restricted universe multiverse\n\
deb [arch=amd64] http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse\n\
deb [arch=armhf,arm64] http://ports.ubuntu.com/ubuntu-ports/ focal main restricted universe multiverse\n\
deb [arch=armhf,arm64] http://ports.ubuntu.com/ubuntu-ports/ focal-updates main restricted universe multiverse\n\
deb [arch=armhf,arm64] http://ports.ubuntu.com/ubuntu-ports/ focal-backports main restricted universe multiverse\n\
deb [arch=armhf,arm64] http://ports.ubuntu.com/ubuntu-ports/ focal-security main restricted universe multiverse"\
 > /etc/apt/sources.list

## Install dependencies
RUN apt-get update && apt-get install -y -f \
    git \
    make \
    curl \
    gnupg \
    pkg-config \
    autoconf \
    libtool \
    openssl \
    g++-arm-linux-gnueabihf \
    binutils-multiarch \
    protobuf-compiler \
    protobuf-compiler-grpc

RUN dpkg --add-architecture armhf &&\
    apt-get update && apt-get install -y -f \
    libgrpc++-dev:armhf \
    libprotobuf-dev:armhf \
    libc-ares-dev:armhf \
    libssl-dev:armhf \
    libsystemd-dev:armhf \
    libgtest-dev:armhf

# Install Edge TPU compiler
RUN echo "deb https://packages.cloud.google.com/apt coral-edgetpu-stable main" | tee /etc/apt/sources.list.d/coral-edgetpu.list &&\
    curl -k https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - &&\
    apt-get update && apt-get install -y --no-install-recommends \
    edgetpu-compiler

# Copy larod library
RUN cp $SYSROOT/lib/liblarod* $LIB &&\
    cp $SYSROOT/include/larod* /usr/include

# Get testdata models
WORKDIR /opt/acap-runtime/testdata

# Generate TSL/SSL test certificate
RUN openssl req -x509 -batch -subj '/CN=localhost' -days 10000 -newkey rsa:4096 -nodes -out server.pem -keyout server.key

# Get SSD Mobilenet V2
ADD https://github.com/google-coral/edgetpu/raw/master/test_data/ssd_mobilenet_v2_coco_quant_postprocess_edgetpu.tflite .
ADD https://github.com/google-coral/edgetpu/raw/master/test_data/ssd_mobilenet_v2_coco_quant_postprocess.tflite .
ADD https://github.com/google-coral/edgetpu/raw/master/test_data/coco_labels.txt .
ADD https://github.com/google-coral/edgetpu/raw/master/test_data/grace_hopper.bmp .

# Get Mobilenet V2
ADD http://download.tensorflow.org/models/tflite_11_05_08/mobilenet_v2_1.0_224_quant.tgz tmp/
ADD https://github.com/google-coral/edgetpu/raw/master/test_data/mobilenet_v2_1.0_224_quant_edgetpu.tflite .
ADD https://github.com/google-coral/edgetpu/raw/master/test_data/imagenet_labels.txt .
RUN cd tmp &&\
    tar -xvf mobilenet_v2_1.0_224_quant.tgz &&\
    mv *.tflite .. &&\
    cd .. && rm -rf tmp

# Get EfficientNet-EdgeTpu (M)
ADD https://storage.googleapis.com/cloud-tpu-checkpoints/efficientnet/efficientnet-edgetpu-M.tar.gz tmp/
RUN cd tmp &&\
    tar -xvf efficientnet-edgetpu-M.tar.gz &&\
    cd efficientnet-edgetpu-M &&\
    edgetpu_compiler --min_runtime_version 13 efficientnet-edgetpu-M_quant.tflite &&\
    mv efficientnet-edgetpu-M_quant*.tflite ../.. &&\
    cd ../.. && rm -rf tmp

## Get Tensorflow
WORKDIR /opt/acap-runtime
ARG TENSORFLOW_DIR=/opt/tensorflow/tensorflow
RUN git clone -b r1.14 https://github.com/tensorflow/tensorflow.git $TENSORFLOW_DIR
RUN git clone -b r1.14 https://github.com/tensorflow/serving.git /opt/tensorflow/serving
RUN mkdir apis &&\
    cd apis &&\
    ln -fs /opt/tensorflow/tensorflow/tensorflow &&\
    ln -fs /opt/tensorflow/serving/tensorflow_serving

## Build and install
COPY . ./
RUN make install

FROM arm32v7/ubuntu:$UBUNTU_VERSION as release
ENV LIB=/usr/lib/arm-linux-gnueabihf
ENV LD_LIBRARY_PATH=/host/lib

COPY --from=api $LIB/ld-*.so $LIB/
COPY --from=api $LIB/ld-linux-armhf.so.* $LIB/
COPY --from=api $LIB/libc-*.so $LIB/
COPY --from=api $LIB/libc.so* $LIB/
COPY --from=api $LIB/libcares.so* $LIB/
COPY --from=api $LIB/libcares.so* $LIB/
COPY --from=api $LIB/libcrypto.so* $LIB/
COPY --from=api $LIB/libdl-*.so $LIB/
COPY --from=api $LIB/libdl.so* $LIB/
COPY --from=api $LIB/libgcc_s.so* $LIB/
COPY --from=api $LIB/libgpr.so* $LIB/
COPY --from=api $LIB/libgrpc.so* $LIB/
COPY --from=api $LIB/libgrpc++.so* $LIB/
COPY --from=api $LIB/libm.so* $LIB/
COPY --from=api $LIB/librt-*.so $LIB/
COPY --from=api $LIB/librt.so* $LIB/
COPY --from=api $LIB/libprotobuf.so* $LIB/
COPY --from=api $LIB/libpthread-*.so $LIB/
COPY --from=api $LIB/libpthread.so* $LIB/
COPY --from=api $LIB/libsystemd.so* $LIB/
COPY --from=api $LIB/libssl.so* $LIB/
COPY --from=api $LIB/libstdc++.so* $LIB/
COPY --from=api $LIB/libz.so.* $LIB/
COPY --from=api /usr/bin/acap-runtime /usr/bin/

FROM release as test
COPY --from=api /usr/bin/acap-runtime.test /usr/bin/
COPY --from=api /opt/acap-runtime/testdata/* /testdata/

# This container is used for finding out what libraries acap-runtime
# needs, and the outcome is the list above of libraries to preserve.
#ENTRYPOINT [ "/usr/bin/ldd",  "/usr/bin/acap-runtime" ]
#CMD ["/usr/bin/acap-runtime"]
