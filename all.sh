#/bin/bash

env PYTHONDONTWRITEBYTECODE=1 &>/dev/null
env TF_CPP_MIN_LOG_LEVEL=1 &>/dev/null

function safe_git {
  if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: safe_git <repo_url> <local_folder> [<branch_name>]"
    return 1
  fi

  local repo_url=$1 local_folder=$2 branch_name=${3:-""} retry_count=3

  if [ -d "$local_folder/.git" ] && git -C "$local_folder" rev-parse &> /dev/null; then
    echo "INFO: Repo $local_folder is valid, performing update."
    git -c core.hooksPath=/dev/null -C "$local_folder" pull && return 0
  else
    echo "INFO: Repo $local_folder is not valid or does not exist, cloning."
    rm -rf "$local_folder"
    for i in $(seq $retry_count); do
      git -c core.hooksPath=/dev/null clone ${branch_name:+-b "$branch_name"} "$repo_url" "$local_folder" && return 0
      echo "NOTICE: git clone failed, retrying in 5 seconds (attempt $i of $retry_count)..."
      sleep 5  # Wait for 5 seconds before retrying
      rm -rf "$local_folder"
    done

    echo "ERROR: All git clone attempts for '$repo_url' failed, please rerun the script." >&2
    exit 1
  fi
}

function safe_fetch {
  local url="$1"
  local output_dir="$2"
  local output_filename="$3"
  local retries=3
  local timeout=120
  local waitretry=5
  local tmp_file="$output_filename.tmp"

  if [[ $# -ne 3 ]]; then
    echo "Usage: safe_fetch <url> <output_dir> <output_filename>"
    return 1
  fi

  if [[ -f "$output_dir/$output_filename" ]]; then
    remote_size=$(curl -Is "$url" | awk '/content-length/ {clen=$2} /x-linked-size/ {xsize=$2} END {if (xsize) print xsize; else print clen;}' | tr -dc '0-9' || echo '')
    local_size=$(stat --format=%s "$output_dir/$output_filename" 2>/dev/null | tr -dc '0-9' || echo '')
    echo "LOCAL_SIZE: $local_size"
    echo "REMOTE_SIZE: $remote_size"
    if [[ $local_size != 0 ]] && [[ "$local_size" -eq "$remote_size" ]]; then
      echo "INFO: local file '$output_filename' is up-to-date, skipping download"
      return 0
    fi
  fi

  mkdir -p "$output_dir"
  for ((i=1; i<=retries; i++)); do
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "$url" -d "$output_dir" -o "$tmp_file" && { mv "$output_dir/$tmp_file" "$output_dir/$output_filename" && echo "INFO: downloaded '$output_filename' to '$output_dir'" && return 0; }
    echo "NOTICE: failed to download '$output_filename', retrying in $waitretry seconds (attempt $i of $retries)..."
    sleep "$waitretry"
  done

  echo "ERROR: failed to download '$output_filename' after $retries attempts, please rerun the script." >&2
  rm -f "$tmp_file"
  exit 1
}

function reset_repos {
    if [ "$#" -lt 1 ]; then
        echo "Usage: reset_repos <base_dir> [<all>]"
        return 1
    fi
    if [ ! -d "$1" ]; then
        echo "Error: The base_dir passed is not a valid path"
        return 1
    fi
    local base_path="$1" all=${2:-""}
    git -C $base_path reset --hard
    git -C $base_path/repositories/stable-diffusion-stability-ai reset --hard
    if [ "$all" = "all" ]; then
      cd $base_path/extensions && find . -maxdepth 1 -type d \( ! -name . \) -exec bash -c "echo '{}' && git -C '{}' reset --hard && git pull" \;
    fi
}

function sed_for {
    if [ "$#" -lt 2 ]; then
        echo "Usage: sed_for <installation|run> <base_dir>"
        return 1
    fi
    local option=$1
    local base_dir=$2
    if [ ! -d "$base_dir" ]; then
        echo "Error: '$base_dir' is not a valid directory"
        return 1
    fi
    if [[ $option == "installation" ]]; then
        sed -i -e 's/    start()/    #start()/g' $base_dir/launch.py
    elif [[ $option == "run" ]]; then
        sed -i -e """/    prepare_environment()/a\    os.system\(f\'''sed -i -e ''\"s/dict()))/dict())).cuda()/g\"'' $base_dir/repositories/stable-diffusion-stability-ai/ldm/util.py''')""" $base_dir/launch.py
        sed -i -e 's/\"sd_model_checkpoint\"\,/\"sd_model_checkpoint\,sd_vae\,CLIP_stop_at_last_layers\"\,/g' $base_dir/modules/shared.py
    else
        echo "Error: Invalid argument '$option'"
        echo "Usage: sed_for <installation|run> <base_dir>"
        return 1
    fi
    sed -i -e 's/checkout {commithash}/checkout --force {commithash}/g' $base_dir/launch.py
}

function prepare_perf_tools {
    local packages=("http://launchpadlibrarian.net/367274644/libgoogle-perftools-dev_2.5-2.2ubuntu3_amd64.deb" "https://launchpad.net/ubuntu/+source/google-perftools/2.5-2.2ubuntu3/+build/14795286/+files/google-perftools_2.5-2.2ubuntu3_all.deb" "https://launchpad.net/ubuntu/+source/google-perftools/2.5-2.2ubuntu3/+build/14795286/+files/libtcmalloc-minimal4_2.5-2.2ubuntu3_amd64.deb" "https://launchpad.net/ubuntu/+source/google-perftools/2.5-2.2ubuntu3/+build/14795286/+files/libgoogle-perftools4_2.5-2.2ubuntu3_amd64.deb")
    regex="/([^/]+)\.deb$"
    install=false
    for package in "${packages[@]}"; do
        echo $package
        if [[ $package =~ $regex ]]; then
          filename=${BASH_REMATCH[1]}
          package_name=$(echo "${BASH_REMATCH[1]}" | cut -d "_" -f 1)
          package_version=$(echo "${BASH_REMATCH[1]}" | cut -d "_" -f 2)
          if dpkg-query -W "$package_name" 2>/dev/null | grep -q "$package_version"; then
            echo "already installed: $package_name with version $package_version, skipping"
            continue
          fi
          #not installed or not the required version
          safe_fetch $package /tmp $package_name.deb
          install=true
        else
          echo "Invalid URL format"
        fi
    done
    apt install -qq libunwind8-dev
    env LD_PRELOAD=libtcmalloc.so &>/dev/null
    $install && dpkg -i /tmp/*.deb
}

function assemble_target_path {
    if [[ "$#" -ne 1 ]]; then
      echo "Usage: assemble_target_path <type>"
      return 1
    fi
    local type=$1
    case $type in
      webui)
        echo $BASEPATH
        ;;
      extensions)
        echo $BASEPATH/extensions
        ;;
      scripts)
        echo $BASEPATH/scripts
        ;;
      embeddings)
        echo $BASEPATH/embeddings
        ;;
      ESRGAN_models)
        echo $BASEPATH/models/ESRGAN
        ;;
      checkpoints)
        echo $BASEPATH/models/Stable-diffusion
        ;;
      hypernetworks)
        echo $BASEPATH/models/hypernetworks
        ;;
      lora)
        echo $BASEPATH/models/Lora
        ;;
      lycoris)
        echo $BASEPATH/models/LyCORIS
        ;;
      vae)
        echo $BASEPATH/models/VAE
        ;;
      clip)
        echo $BASEPATH/models/CLIP
        ;;
      cn_models)
        echo $BASEPATH/extensions/sd-webui-controlnet/models
        ;;
      *)
        echo "Error: Unrecognized template config type $type."
        exit 1
        ;;
    esac
}

function install_from_template {
    if [ "$#" -ne 1 ]; then
      echo "Usage: install_from_template <config_path>"
      return 1
    fi
    local config_path=$1
    if [[ -f $config_path ]]; then
      mapfile -t lines < $config_path
      for line in "${lines[@]}"
      do
          echo "->Processing template config line: $line"
          trimmed_url=$(echo "$line" | tr -d ' ' | cut -d "#" -f 1)
          base_name=$(basename $trimmed_url)
          if [[ ! -z $trimmed_url ]]; then
            type=$(basename $config_path | cut -d "." -f 1)
            git ls-remote $trimmed_url &> /dev/null
            if [[ $? -eq 0 ]]; then
              #this is a git repo
              branch=$(echo "$line" | grep -q "#" && echo "$line" | cut -d "#" -f 2)
              echo "->This is a $type component Git repo with branch $branch, will be saved to $(assemble_target_path $type)"
              if [[ $type == "webui" ]]; then
                safe_git "$trimmed_url" $(assemble_target_path $type) ${branch:+$branch}
                break
              else
                safe_git "$trimmed_url" $(assemble_target_path $type)/$base_name ${branch:+$branch}
              fi
            else
              echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
              safe_fetch $trimmed_url $(assemble_target_path $type) $base_name
            fi
          fi
      done
    fi
}

function prepare_pip_deps {
    pip install -q torch==2.0.0+cu118 torchvision==0.15.1+cu118 torchaudio==2.0.1+cu118 torchtext==0.15.1 torchdata==0.6.0 --extra-index-url https://download.pytorch.org/whl/cu118 -U
    pip install -q xformers==0.0.18 triton==2.0.0 -U
}

function prepare_fuse_dir {
    #Prepare drive fusion MOVE THIS TOLATER
    mkdir /content/fused-models
    mkdir /content/models
    mkdir /content/fused-lora
    mkdir /content/lora
    unionfs-fuse $BASEPATH/models/Stable-diffusion=RW:/content/models=RW /content/fused-models
    unionfs-fuse $BASEPATH/extensions/sd-webui-additional-networks/models/lora=RW:$BASEPATH/models/Lora=RW:/content/lora=RW /content/fused-lora
}

function install {
    #Prepare runtime
    component_types=( "webui" "extensions" "scripts" "embeddings" "ESRGAN_models" "checkpoints" "hypernetworks" "lora" "lycoris" "vae" "clip" "cn_models" )
    for component_type in "${component_types[@]}"
    do
      template_path=$1
      config_path=$template_path/$component_type.txt
      echo $config_path
      if [[ -f $config_path ]]; then
        install_from_template $config_path
      fi
    done

    reset_repos $BASEPATH all

    #Install Dependencies
    sed_for installation $BASEPATH
    cd $BASEPATH && python launch.py --skip-torch-cuda-test && echo "Installation Completed" > $BASEPATH/.install_status
}

function run {
    #Install google perf tools
    prepare_perf_tools

    prepare_pip_deps
    prepare_fuse_dir

    #Healthcheck and update all repos
    reset_repos $BASEPATH

    #Prepare for running
    sed_for run $BASEPATH

    cd $BASEPATH && python launch.py --listen --share --xformers --enable-insecure-extension-access --theme dark --clip-models-path $BASEPATH/models/CLIP
}

BASEPATH=/content/drive/MyDrive/SD
TEMPLATE_LOCATION="https://github.com/AI-skimos/3line-colab-sd"
TEMPLATE_NAME="camenduru"
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -f|--force-install)
        FORCE_INSTALL=true
        shift
        ;;
        -l|--template-location)
        TEMPLATE_LOCATION="$2"
        git ls-remote $TEMPLATE_LOCATION &> /dev/null
        if [[ $? -ne 0 && ! -d $TEMPLATE_LOCATION ]]; then
          echo "Error: Specified template location is neither a valid git repo, nor a valid local path: $TEMPLATE_LOCATION"
          exit 1
        fi
        shift 
        shift
        ;;
        -n|--template-name)
        TEMPLATE_NAME="$2"
        shift
        shift
        ;;
        -i|--install-path)
        BASEPATH="$2"
        shift
        shift
        ;;
        *)
        echo "Usage: $0 [-f|--force-install] [-l|--template-location <git repo|directory>] [-n|--template-name <name>] [-i|--install-path <directory>]"
        echo "Options:"
        echo "-f, --force-install          Force reinstall"
        echo "-l, --template-location      Location of the template repo or local directory (default: https://github.com/AI-skimos/3line-colab-sd)"
        echo "-n, --template-name          Name of the template to install (default: templates/camenduru)"
        echo "-i, --install-path           Path to install SD (default: /content/drive/MyDrive/SD)"
        exit 1
        ;;
    esac
done

if [[ -z "$FORCE_INSTALL" ]]; then FORCE_INSTALL=false; fi

git ls-remote $TEMPLATE_LOCATION &> /dev/null
if [[ $? -eq 0 ]]; then
  #location is a git repo
  TEMPLATE_PATH=/tmp/$(basename $TEMPLATE_LOCATION)
  safe_git $TEMPLATE_LOCATION $TEMPLATE_PATH
else
  TEMPLATE_PATH=$TEMPLATE_LOCATION
fi

echo $(find "$TEMPLATE_PATH" -maxdepth 2 -type d -name "$TEMPLATE_NAME" -print -quit)
FINAL_PATH=$(find "$TEMPLATE_PATH" -maxdepth 2 -type d -name "$TEMPLATE_NAME" -print -quit)
if [ -z $FINAL_PATH ]; then
  echo "Error: $TEMPLATE_PATH does not contain a template named $TEMPLATE_NAME. Please confirm you have correctly specified template location and template name."
  exit 1
fi

echo "FORCE_INSTALL: $FORCE_INSTALL"
echo "TEMPLATE_LOCATION: $TEMPLATE_LOCATION"
echo "TEMPLATE_NAME: $TEMPLATE_NAME"
echo "FINAL_PATH: $FINAL_PATH"

#Update packages
apt -y update -qq && apt -y install -qq unionfs-fuse libcairo2-dev pkg-config python3-dev aria2

if [ "$FORCE_INSTALL" = true ] || [ ! -e "$BASEPATH/.install_status" ] || ! grep -qs "Installation Completed" "$BASEPATH/.install_status"; then
    install $FINAL_PATH
fi

run
