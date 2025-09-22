# ========================
# Stage 1: Build TensorFlow
# ========================
# Core build args (defaults allow building without external .env or scripts)
ARG PYTHON_VERSION=3.10
ARG TARGET_PLATFORM=linux/arm64
ARG TENSORFLOW_VERSION=v2.19.0
FROM --platform=${TARGET_PLATFORM:-linux/arm64} python:${PYTHON_VERSION:-3.10} AS build

# TensorFlow config flags (defaults mirror previous .env)
ARG TF_NEED_CUDA=0
ARG TF_ENABLE_XLA=0
ARG TF_NEED_ROCM=0
ARG TF_NEED_MPI=0
ARG TF_NEED_OPENCL_SYCL=0
ARG TF_NEED_CLANG=1
ARG CC_OPT_FLAGS="-march=native"
# Wheel platform tag for the generated wheel (PEP 600 manylinux)
ARG WHEEL_PLATFORM=manylinux2014_aarch64

ENV BUILD_DIR=/usr/local/src/tensorflow
ARG DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt update && apt install -y --no-install-recommends \
    build-essential python3-dev pkg-config zip zlib1g-dev unzip curl \
    wget git htop openjdk-21-jdk liblapack3 libblas3 libhdf5-dev npm ca-certificates \
    clang-18 llvm-18 lld patchelf golang && \
    rm -rf /var/lib/apt/lists/*

# Python and Bazel dependencies
RUN --mount=type=cache,id=tf-pip-cache,target=/root/.cache/pip \
    pip install --upgrade pip && \
    pip install six numpy grpcio h5py packaging opt_einsum wheel requests

RUN --mount=type=cache,id=tf-npm-cache,target=/root/.npm \
    npm install -g @bazel/bazelisk

# Clone TensorFlow source
RUN mkdir -p "${BUILD_DIR}" && \
    git -c advice.detachedHead=false init "${BUILD_DIR}" && \
    cd "${BUILD_DIR}" && \
    git remote add origin https://github.com/tensorflow/tensorflow.git && \
    git fetch --depth 1 origin "${TENSORFLOW_VERSION}" && \
    git checkout --detach FETCH_HEAD

WORKDIR ${BUILD_DIR}

# Configure TensorFlow (non-interactive)
ENV PYTHON_BIN_PATH=/usr/local/bin/python
ENV USE_DEFAULT_PYTHON_LIB_PATH=1
ENV TF_NEED_CUDA=${TF_NEED_CUDA}
ENV TF_ENABLE_XLA=${TF_ENABLE_XLA}
ENV TF_NEED_ROCM=${TF_NEED_ROCM}
ENV TF_NEED_MPI=${TF_NEED_MPI}
ENV TF_NEED_OPENCL_SYCL=${TF_NEED_OPENCL_SYCL}
ENV TF_DOWNLOAD_CLANG=0
ENV TF_NEED_CLANG=${TF_NEED_CLANG}
ENV CC_OPT_FLAGS="${CC_OPT_FLAGS}"
ENV TF_SET_ANDROID_WORKSPACE=0
ENV CLANG_COMPILER_PATH=/usr/bin/clang-18
ENV TF_CXX_FLAGS="-Wno-unsupported-gnu-property -Wno-error=unused-command-line-argument"

RUN echo "build --linkopt=-Wl,--undefined-version" >> .bazelrc

RUN ./configure

# Fix missing <cstdint> library
RUN sed -i '1i#include <cstdint>' third_party/xla/third_party/tsl/tsl/platform/denormal.cc

# Build TensorFlow wheel
RUN --mount=type=cache,id=tf-bazel-cache,target=/root/.cache/bazel \
    bazel build -c opt --jobs=6 --verbose_failures \
    --define=with_xla_support=false \
    --copt=-Wno-gnu-offsetof-extensions \
    //tensorflow/tools/pip_package:wheel && \
    mkdir -p /tmp/tensorflow_pkg && \
    cp -v bazel-bin/tensorflow/tools/pip_package/wheel_house/*.whl /tmp/tensorflow_pkg/

# =========================
# Stage 2: Final slim image
# =========================
FROM --platform=${TARGET_PLATFORM:-linux/arm64} python:${PYTHON_VERSION:-3.10}

# Copy wheel from build stage
COPY --from=build /tmp/tensorflow_pkg /tmp/tensorflow_pkg

# Install wheel
RUN pip install /tmp/tensorflow_pkg/tensorflow-*.whl && \
    rm -rf /tmp/tensorflow_pkg

CMD ["python3"]