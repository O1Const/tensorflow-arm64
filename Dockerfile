# ========================
# Stage 1: Build TensorFlow
# ========================
ARG PYTHON_VERSION=3.10
ARG TARGET_PLATFORM=linux/arm64
FROM --platform=${TARGET_PLATFORM} python:${PYTHON_VERSION} AS build

ARG TENSORFLOW_VERSION=v2.15.0
ENV BUILD_DIR=/usr/local/src/tensorflow
ARG DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt update && apt install -y --no-install-recommends \
    build-essential python3-dev pkg-config zip zlib1g-dev unzip curl \
    wget git htop openjdk-17-jdk liblapack3 libblas3 libhdf5-dev npm ca-certificates \
    clang lld patchelf && \
    rm -rf /var/lib/apt/lists/*

# Python and Bazel dependencies
RUN pip install --upgrade pip && \
    pip install six numpy grpcio h5py packaging opt_einsum wheel requests

RUN npm install -g @bazel/bazelisk

# Clone TensorFlow source
RUN mkdir -p ${BUILD_DIR} && \
    git clone --depth 1 --branch ${TENSORFLOW_VERSION} https://github.com/tensorflow/tensorflow.git ${BUILD_DIR}

WORKDIR ${BUILD_DIR}

# Configure TensorFlow (non-interactive)
ENV PYTHON_BIN_PATH=/usr/local/bin/python
ENV USE_DEFAULT_PYTHON_LIB_PATH=1
ENV TF_NEED_CUDA=0
ENV TF_ENABLE_XLA=0
ENV TF_NEED_ROCM=0
ENV TF_NEED_MPI=0
ENV TF_NEED_OPENCL_SYCL=0
ENV TF_DOWNLOAD_CLANG=0
ENV TF_NEED_CLANG=1
ENV CC_OPT_FLAGS="-march=native"
ENV TF_SET_ANDROID_WORKSPACE=0
ENV CLANG_COMPILER_PATH=/usr/bin/clang

RUN ./configure

# Build TensorFlow wheel
RUN --mount=type=cache,target=/root/.cache/bazel \
    bazel build -c opt --jobs=4 --verbose_failures //tensorflow/tools/pip_package:build_pip_package && \
    ./bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg

# =========================
# Stage 2: Final slim image
# =========================
FROM --platform=${TARGET_PLATFORM} python:${PYTHON_VERSION}

# Copy wheel from build stage
COPY --from=build /tmp/tensorflow_pkg /tmp/tensorflow_pkg

# Install wheel
RUN pip install /tmp/tensorflow_pkg/tensorflow-*.whl && \
    rm -rf /tmp/tensorflow_pkg

CMD ["python3"]