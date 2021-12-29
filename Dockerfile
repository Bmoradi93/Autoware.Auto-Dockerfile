FROM nvidia/cuda:11.4.2-devel-ubuntu20.04

ENV CI_BUILD_PYTHON python
ARG CACHE_STOP=1
ARG CHECKOUT_TF_SRC=0
ENV DEBIAN_FRONTEND noninteractive
ARG BAZEL_VERSION=3.7.2
ENV LANG C.UTF-8

RUN apt-get update && apt-get install -y curl sudo lsb-release
RUN curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh 
RUN curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | sudo apt-key add -
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key  -o /usr/share/keyrings/ros-archive-keyring.gpg
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
RUN sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list'

# Install apt packages
COPY ./dependencies.pkg /opt/dependencies.pkg
RUN apt-get update && \
    apt-get install -y \
        $(cat /opt/dependencies.pkg) \
    && rm -rf /var/lib/apt/lists/* /opt/dependencies.pkg

#Install PIP Packages
ADD ./pip.txt /opt/pip.txt
RUN python3 -m pip install --upgrade pip &&\
    python3 -m pip --no-cache-dir install -r /opt/pip.txt

RUN chmod a+w /etc/passwd /etc/group
RUN test "${CHECKOUT_TF_SRC}" -eq 1 && git clone https://github.com/tensorflow/tensorflow.git /tensorflow_src || true
RUN ln -s $(which python3) /usr/local/bin/python

# Install bazel
RUN mkdir /bazel && \
    wget -O /bazel/installer.sh "https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-installer-linux-x86_64.sh" && \
    wget -O /bazel/LICENSE.txt "https://raw.githubusercontent.com/bazelbuild/bazel/master/LICENSE" && \
    chmod +x /bazel/installer.sh && \
    /bazel/installer.sh && \
    rm -f /bazel/installer.sh

# # Install Tensorflow
# ADD ./models /opt/models
# RUN (cd /opt/models/research && curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && python3 get-pip.py --force-reinstall && protoc object_detection/protos/*.proto --python_out=. && cp object_detection/packages/tf2/setup.py . && python3 -m pip install --use-feature=2020-resolver .)
# RUN git lfs install

RUN echo "Acquire::GzipIndexes \"false\"; Acquire::CompressionTypes::Order:: \"gz\";" > /etc/apt/apt.conf.d/docker-gzip-indexes

USER $USERNAME
WORKDIR /home/$USERNAME
SHELL ["/bin/bash", "-c"]

RUN echo "source /opt/ros/foxy/setup.bash" >> ~/.bashrc && \
    echo "export ROS_DOMAIN_ID=100" >> ~/.bashrc && \
    echo "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" >> ~/.bashrc && \
    echo "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" >> ~/.bashrc && \
    source ~/.bashrc

# Install cudNN 
COPY libcudnn8_8.2.0.53-1+cuda11.3_amd64.deb /root
RUN cd /root && dpkg -i libcudnn8_8.2.0.53-1+cuda11.3_amd64.deb

RUN sudo rosdep init && rosdep update 

RUN source /opt/ros/foxy/setup.bash && \
    git clone https://gitlab.com/autowarefoundation/autoware.auto/AutowareAuto.git && \
    cd AutowareAuto && \
    sudo apt-get update && \
    vcs import < autoware.auto.foxy.repos && \
    rosdep install -y -i --from-paths src && \
    colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release && \
    sudo apt-get clean && \
    sudo rm -rf /var/lib/apt/lists/*

RUN echo "source /opt/ros/foxy/setup.bash" >> ~/.bashrc && \
    echo "source ~/AutowareAuto/install/setup.bash" >> ~/.bashrc && \
    echo "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" >> ~/.bashrc && \
    echo "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" >> ~/.bashrc && \
    source ~/.bashrc