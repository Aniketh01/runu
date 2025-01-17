#!/bin/bash

if [ $TRAVIS_OS_NAME != "osx" ] ; then
    echo "containerd and ctr runtime test only support with osx host. Skipped"
    exit 0
fi

. $(dirname "${BASH_SOURCE[0]}")/common.sh

CTR_ARGS="--rm --runtime=io.containerd.runtime.v1.linux --fifo-dir /tmp/ctrd --env RUMP_VERBOSE=1"
CTR_GLOBAL_OPT="--debug -a /tmp/ctrd/run/containerd/containerd.sock"

# build custom containerd
fold_start test.containerd.0 "containerd build"
HOMEBREW_NO_AUTO_UPDATE=1 brew install libos-nuse/lkl/containerd
fold_end test.containerd.0 ""

# prepare containerd
fold_start test.containerd.0 "boot containerd"
    git clone https://gist.github.com/aba357f73da4e14bc3f5cbeb00aeaea4.git /tmp/containerd-config
    cp /tmp/containerd-config/config.toml /tmp/
    sed "s/501/$UID/" /tmp/config.toml > /tmp/a
    mv /tmp/a /tmp/config.toml

    mkdir /tmp/containerd-shim
    sudo killall containerd || true
    containerd -l debug -c /tmp/config.toml &
    sleep 3
    killall containerd
    sudo containerd -l debug -c /tmp/config.toml &
    sleep 3
    chmod 755 /tmp/ctrd
    ls -lRa /tmp/ctrd
fold_end test.containerd.0 ""


# pull an image
fold_start test.containerd.0 "pull image"
    ctr -a /tmp/ctrd/run/containerd/containerd.sock i pull \
       docker.io/thehajime/runu-base:$DOCKER_IMG_VERSION
    ctr -a /tmp/ctrd/run/containerd/containerd.sock i pull \
        --platform=linux/amd64 docker.io/library/alpine:latest
fold_end test.containerd.0 "pull image"

# test hello-world
fold_start test.containerd.1 "test hello"
    ctr $CTR_GLOBAL_OPT run $CTR_ARGS \
        docker.io/thehajime/runu-base:$DOCKER_IMG_VERSION hello hello
fold_end test.containerd.1

# test ping
fold_start test.containerd.2 "test ping"
    ctr $CTR_GLOBAL_OPT run $CTR_ARGS \
        --env LKL_ROOTFS=imgs/python.iso \
        docker.io/thehajime/runu-base:$DOCKER_IMG_VERSION hello \
        ping -c5 127.0.0.1
fold_end test.containerd.2

# test python
# XXX: PYTHONHASHSEED=1 is workaround for slow read of getrandom() on 4.19
# (4.16 doesn't have such)
fold_start test.containerd.3 "test python"
    ctr $CTR_GLOBAL_OPT run $CTR_ARGS \
        --env HOME=/ --env PYTHONHOME=/python \
        --env LKL_ROOTFS=imgs/python.img \
        --env PYTHONHASHSEED=1 \
        docker.io/thehajime/runu-base:$DOCKER_IMG_VERSION hello \
        python -c "print(\"hello world from python(docker-runu)\")"
fold_end test.containerd.3

# test nginx
fold_start test.containerd.4 "test nginx"
    ctr $CTR_GLOBAL_OPT run $CTR_ARGS \
        --env LKL_ROOTFS=imgs/data.iso \
        docker.io/thehajime/runu-base:$DOCKER_IMG_VERSION hello \
        nginx &
sleep 3
killall -9 ctr
fold_end test.containerd.4

# test alpine
# prepare RUNU_AUX_DIR
create_runu_aux_dir

fold_start test.containerd.5 "test alpine Linux on darwin"
    ctr $CTR_GLOBAL_OPT run $CTR_ARGS \
        --env RUNU_AUX_DIR=$RUNU_AUX_DIR --env LKL_USE_9PFS=1 \
        docker.io/library/alpine:latest alpine1 /bin/busybox ls -l &
    # XXX: fork/execve is still buggy not to properly exit (and hungs)
    sleep 3
    killall -9 ctr
fold_end test.containerd.5
