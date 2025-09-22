# tensorflow-arm64

Build TensorFlow from source for arm64 (Apple Silicon and other ARM64 targets) using a single self‑contained Dockerfile.

## Quick start (Apple Silicon)

- Standard build (defaults: Python 3.10, TensorFlow v2.19.0, arm64):

  docker build -t tensorflow:v2.19.0-arm64-custom .

- Using Buildx with explicit platform:

  docker buildx build --platform linux/arm64 -t tensorflow:v2.19.0-arm64-custom .

After the build, run an interactive shell:

  docker run --rm -it tensorflow:v2.19.0-arm64-custom python -c "import tensorflow as tf; print(tf.__version__)"

Quick smoke test (verifies basic ops execute):

  docker run --rm -it tensorflow:v2.19.0-arm64-custom python -c "import tensorflow as tf; a=tf.random.uniform([64,64]); b=tf.random.uniform([64,64]); print('matmul OK, shape=', tf.linalg.matmul(a,b).shape)"

## Customizing the build

The Dockerfile exposes arguments so you can customize the build directly on the command line. All of them have sensible defaults matching the previous .env file.

- Core args:
  - PYTHON_VERSION (default 3.10)
  - TARGET_PLATFORM (default linux/arm64)
  - TENSORFLOW_VERSION (default v2.19.0)

- TensorFlow config flags:
  - TF_NEED_CUDA (default 0)
  - TF_ENABLE_XLA (default 0)
  - TF_NEED_ROCM (default 0)
  - TF_NEED_MPI (default 0)
  - TF_NEED_OPENCL_SYCL (default 0)
  - TF_NEED_CLANG (default 1)
  - CC_OPT_FLAGS (default -march=native)

Example: build TensorFlow v2.19.0 with Python 3.11 and XLA enabled:

  docker build \
    --build-arg PYTHON_VERSION=3.11 \
    --build-arg TF_ENABLE_XLA=1 \
    -t tensorflow:v2.19.0-py311-xla-arm64 .

## Notes

- Platform: The Dockerfile sets linux/arm64 by default. You can also use Buildx and pass --platform linux/arm64 explicitly.
- Tagging: Image tags are up to you; the previous script auto-generated tags but that logic is better handled at the docker build command line.
- Performance: The Dockerfile uses BuildKit cache mounts (with persistent ids) for pip, npm, and Bazel to speed up incremental builds and let you resume faster after errors. Ensure DOCKER_BUILDKIT=1 (Docker Desktop enables this by default).

### Resuming faster after build errors

- The Dockerfile mounts caches with stable ids:
  - pip: /root/.cache/pip (id=tf-pip-cache)
  - npm: /root/.npm (id=tf-npm-cache)
  - Bazel: /root/.cache/bazel (id=tf-bazel-cache)
  These caches persist across builds, so if a step fails you can rerun the build and Bazel/Python/npm will reuse previous work.

- For even better caching across machines/CI runs, use Buildx cache export/import:

  docker buildx build \
    --platform linux/arm64 \
    --cache-to=type=local,dest=.buildx-cache,mode=max \
    --cache-from=type=local,src=.buildx-cache \
    -t tensorflow:v2.19.0-arm64-custom .

  The first run will populate .buildx-cache; subsequent runs will reuse it. You can also use type=registry for a remote cache (e.g., on CI).

- Tip: Changing TENSORFLOW_VERSION or major toolchain components may invalidate parts of the cache, but Bazel’s cache will still significantly reduce rebuild time by reusing unaffected artifacts.