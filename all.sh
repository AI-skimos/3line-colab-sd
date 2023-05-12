#/bin/bash

env PYTHONDONTWRITEBYTECODE=1 &>/dev/null
env TF_CPP_MIN_LOG_LEVEL=1 &>/dev/null
#BASEPATH=/content/drive/MyDrive/SD
BASEPATH=/tmp/SD

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
  local tmp_file="$output_dir/$output_filename.tmp"

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
    wget -q --show-progress --continue --tries=3 --timeout="$timeout" --waitretry="$waitretry" --no-dns-cache -O "$tmp_file" "$url" && { mv "$tmp_file" "$output_dir/$output_filename" && echo "INFO: downloaded '$output_filename' to '$output_dir'" && return 0; }
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

function assemble_path {
    if [[ "$#" -ne 1 ]]; then
      echo "Usage: assemble_path <type>"
      return 1
    fi
    local type=$1
    case $type in
      webui)
        echo $BASEPATH
        ;;
      extension)
        echo $BASEPATH/extensions
        ;;
      extra_script)
        echo $BASEPATH/scripts
        ;;
      embedding)
        echo $BASEPATH/embeddings
        ;;
      ESRGAN_model)
        echo $BASEPATH/models/ESRGAN
        ;;
      checkpoint)
        echo $BASEPATH/models/Stable-Diffusion
        ;;
      hypernetwork)
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
      cn_model)
        echo $BASEPATH/extensions/sd-webui-controlnet/models
        ;;
      *)
        echo "Error: Unrecognized template config type $type."
        exit 1
        ;;
    esac
}
assemble_path webui
assemble_path hypernetwork
assemble_path ESRGAN_model
assemble_path extra_script
assemble_path embedding
assemble_path extension
assemble_path model
assemble_path lora
assemble_path lycoris
assemble_path vae
function install_from_template {
    if [ "$#" -lt 2 ]; then
      echo "Usage: install_from_template <template_path> <type>"
      return 1
    fi
    local template_path=$1
    local type=$2

    config_path=$template_path/$type.txt
    if [[ -f $config_path ]]; then
      mapfile -t lines < $config_path
      for line in "${lines[@]}"
      do
          trimmed_url=$(echo "$trimmed" | tr -d ' ' | cut -d "#" -f 1)
          base_name=$(basename $trimmed_url)
          if [[ -z $trimmed_url ]]; then
            git ls-remote $trimmed_url &> /dev/null
            if [[ $? -eq 0 ]]; then
              #this is a git repo
              branch=$(grep -q "#" && echo "${line#*#}")
              safe_git "$trimmed_url" $(assemble_path $type)/$base_name ${branch:+$branch}
            else
              safe_fetch $trimmed_url $(assemble_path $type) $base_name
            fi
          fi
      done
    fi
}

config_path=templates/camenduru
function install_webui {
    path=$config_path/webui.txt
    if [[ -f $path ]]; then
      mapfile -t lines < $path
      if [[ ${#lines[@]} -ge 1 ]]; then
        repo=$(echo "${lines[0]}" | cut -d "#" -f 1)
        branch=$(echo "${lines[0]}" | grep -q "#" && echo "${lines[0]}" | cut -d "#" -f 2)
        safe_git "$repo" "$BASEPATH" ${branch:+$branch}
      else
        echo "Error: wrong format for template config file: $path"
      fi
    else
      safe_git https://github.com/AUTOMATIC1111/stable-diffusion-webui $BASEPATH
    fi
}
#install_webui

function install_embeddings {
    path=$config_path/embeddings.txt
    if [[ -f $path ]]; then
      mapfile -t lines < $path
      for line in "${lines[@]}"
      do
          repo=$(echo "${lines[0]}" | cut -d "#" -f 1)
          branch=$(echo "${lines[0]}" | grep -q "#" && echo "${lines[0]}" | cut -d "#" -f 2)
          safe_git "$repo" "$BASEPATH/embeddings" ${branch:+$branch}
      done
    fi
}
#install_embeddings

function install_ESRGAN_models {
    path=$config_path/ESRGAN_models.txt
    if [[ -f $path ]]; then
      mapfile -t lines < $path
      for line in "${lines[@]}"
      do
          safe_fetch $line $BASEPATH/models/ESRGAN $(echo "$line" | awk -F/ '{print $NF}')
      done
    fi
}

function install_extra_scripts {
    path=$config_path/extra_scripts.txt
    if [[ -f $path ]]; then
      mapfile -t lines < $path
      for line in "${lines[@]}"
      do
          safe_fetch $line $BASEPATH/scripts $(echo "$line" | awk -F/ '{print $NF}')
      done
    fi
}

function install_extensions {
    safe_git https://github.com/deforum-art/deforum-for-automatic1111-webui $BASEPATH/extensions/deforum-for-automatic1111-webui
    path=$config_path/extensions.txt
    if [[ -f $path ]]; then
      mapfile -t lines < $path
      for line in "${lines[@]}"
      do
          repo=$(echo "${lines[0]}" | cut -d "#" -f 1)
          branch=$(echo "${lines[0]}" | grep -q "#" && echo "${lines[0]}" | cut -d "#" -f 2)
          safe_git "$repo" "$BASEPATH/extensions" ${branch:+$branch}
      done
    fi
}

function install_cn_models {
    safe_fetch https://huggingface.co/ckpt/ControlNet-v1-1/resolve/main/control_v11f1e_sd15_tile_fp16.safetensors $BASEPATH/extensions/sd-webui-controlnet/models control_v11f1e_sd15_tile_fp16.safetensors
    #safe_fetch https://huggingface.co/ckpt/ControlNet-v1-1/resolve/main/control_v11p_sd15_canny_fp16.safetensors $BASEPATH/extensions/sd-webui-controlnet/models control_v11p_sd15_canny_fp16.safetensors
    #safe_fetch https://huggingface.co/ckpt/ControlNet-v1-1/resolve/main/control_v11p_sd15_openpose_fp16.safetensors $BASEPATH/extensions/sd-webui-controlnet/models control_v11p_sd15_openpose_fp16.safetensors
    #safe_fetch https://huggingface.co/ckpt/ControlNet-v1-1/resolve/main/control_v11p_sd15_seg_fp16.safetensors $BASEPATH/extensions/sd-webui-controlnet/models control_v11p_sd15_seg_fp16.safetensors
}

function install_checkpoints {
    #Download Model & VAE
    safe_fetch https://huggingface.co/XpucT/Deliberate/resolve/main/Deliberate_v2.safetensors $BASEPATH/models/Stable-diffusion Deliberate_v2.safetensors

}

function install_vae {
    safe_fetch https://huggingface.co/Yukihime256/840000/resolve/main/vae-ft-mse-840000-ema-pruned.ckpt $BASEPATH/models/VAE vae-ft-mse-840000-ema-pruned.ckpt
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

function prepare_clip {
    mkdir -p $BASEPATH/models/CLIP
    safe_fetch https://openaipublic.azureedge.net/clip/models/b8cca3fd41ae0c99ba7e8951adf17d267cdb84cd88be6f7c2e0eca1737a03836/ViT-L-14.pt $BASEPATH/models/CLIP ViT-L-14.pt
}

function install {
    #Prepare runtime
    install_webui
    install_embeddings
    install_ESRGAN_models
    install_extra_scripts
    install_cn_models
    install_extensions

    install_from_template camenduru webui
    install_from_template camenduru embeddings


    reset_repos $BASEPATH all

    install_checkpoints
    install_vae

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

    prepare_clip

    cd $BASEPATH && python launch.py --listen --opt-sdp-attention --enable-insecure-extension-access --theme dark --gradio-queue --clip-models-path $BASEPATH/models/CLIP --multiple
}

force=false
while getopts "f" opt; do
  case ${opt} in
    f)
      force=true
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

#Update packages
#apt -y update -qq && apt -y install -qq unionfs-fuse libcairo2-dev pkg-config python3-dev

#if [ "$force" = true ] || [ ! -e "$BASEPATH/.install_status" ] || ! grep -qs "Installation Completed" "$BASEPATH/.install_status"; then
#    install
#fi

#run
