#/bin/bash

env PYTHONDONTWRITEBYTECODE=1 &>/dev/null
env TF_CPP_MIN_LOG_LEVEL=1 &>/dev/null
BASEPATH=/content/drive/MyDrive/SD

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
    #cd $base_path && pwd && git reset --hard && git pull
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
function install_perf_tools {
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

function install {
    #Prepare runtime
    safe_git https://github.com/camenduru/stable-diffusion-webui $BASEPATH v2.1
    safe_git https://huggingface.co/embed/negative $BASEPATH/embeddings/negative
    safe_git https://huggingface.co/embed/lora $BASEPATH/models/Lora/positive
    safe_fetch https://huggingface.co/embed/upscale/resolve/main/4x-UltraSharp.pth $BASEPATH/models/ESRGAN 4x-UltraSharp.pth
    safe_fetch https://raw.githubusercontent.com/camenduru/stable-diffusion-webui-scripts/main/run_n_times.py $BASEPATH/scripts run_n_times.py
    safe_git https://github.com/deforum-art/deforum-for-automatic1111-webui $BASEPATH/extensions/deforum-for-automatic1111-webui
    safe_git https://github.com/camenduru/stable-diffusion-webui-images-browser $BASEPATH/extensions/stable-diffusion-webui-images-browser
    safe_git https://github.com/camenduru/stable-diffusion-webui-huggingface $BASEPATH/extensions/stable-diffusion-webui-huggingface
    safe_git https://github.com/camenduru/sd-civitai-browser $BASEPATH/extensions/sd-civitai-browser
    safe_git https://github.com/kohya-ss/sd-webui-additional-networks $BASEPATH/extensions/sd-webui-additional-networks
    safe_git https://github.com/Mikubill/sd-webui-controlnet $BASEPATH/extensions/sd-webui-controlnet
    safe_git https://github.com/fkunn1326/openpose-editor $BASEPATH/extensions/openpose-editor
    safe_git https://github.com/jexom/sd-webui-depth-lib $BASEPATH/extensions/sd-webui-depth-lib
    safe_git https://github.com/hnmr293/posex $BASEPATH/extensions/posex
    safe_git https://github.com/nonnonstop/sd-webui-3d-open-pose-editor $BASEPATH/extensions/sd-webui-3d-open-pose-editor
    safe_git https://github.com/camenduru/sd-webui-tunnels $BASEPATH/extensions/sd-webui-tunnels
    safe_git https://github.com/etherealxx/batchlinks-webui $BASEPATH/extensions/batchlinks-webui
    safe_git https://github.com/camenduru/stable-diffusion-webui-catppuccin $BASEPATH/extensions/stable-diffusion-webui-catppuccin
    safe_git https://github.com/KohakuBlueleaf/a1111-sd-webui-locon $BASEPATH/extensions/a1111-sd-webui-locon
    safe_git https://github.com/AUTOMATIC1111/stable-diffusion-webui-rembg $BASEPATH/extensions/stable-diffusion-webui-rembg
    safe_git https://github.com/ashen-sensored/stable-diffusion-webui-two-shot $BASEPATH/extensions/stable-diffusion-webui-two-shot
    safe_git https://github.com/camenduru/sd_webui_stealth_pnginfo $BASEPATH/extensions/sd_webui_stealth_pnginfo
    safe_git https://github.com/thomasasfk/sd-webui-aspect-ratio-helper  $BASEPATH/extensions/sd-webui-aspect-ratio-helper
    safe_git https://github.com/dtlnor/stable-diffusion-webui-localization-zh_CN $BASEPATH/extensions/stable-diffusion-webui-localization-zh_CN
    safe_git https://github.com/AI-skimos/sd-webui-prompt-sr-range $BASEPATH/extensions/sd-webui-prompt-sr-range
    reset_repos $BASEPATH all

    #Download Controlnet Models
    safe_fetch https://huggingface.co/ckpt/ControlNet-v1-1/resolve/main/control_v11f1e_sd15_tile_fp16.safetensors $BASEPATH/extensions/sd-webui-controlnet/models control_v11f1e_sd15_tile_fp16.safetensors
    #safe_fetch https://huggingface.co/ckpt/ControlNet-v1-1/resolve/main/control_v11p_sd15_canny_fp16.safetensors $BASEPATH/extensions/sd-webui-controlnet/models control_v11p_sd15_canny_fp16.safetensors
    #safe_fetch https://huggingface.co/ckpt/ControlNet-v1-1/resolve/main/control_v11p_sd15_openpose_fp16.safetensors $BASEPATH/extensions/sd-webui-controlnet/models control_v11p_sd15_openpose_fp16.safetensors
    #safe_fetch https://huggingface.co/ckpt/ControlNet-v1-1/resolve/main/control_v11p_sd15_seg_fp16.safetensors $BASEPATH/extensions/sd-webui-controlnet/models control_v11p_sd15_seg_fp16.safetensors

    #Download Model & VAE
    safe_fetch https://huggingface.co/XpucT/Deliberate/resolve/main/Deliberate_v2.safetensors $BASEPATH/models/Stable-diffusion Deliberate_v2.safetensors
    safe_fetch https://huggingface.co/Yukihime256/840000/resolve/main/vae-ft-mse-840000-ema-pruned.ckpt $BASEPATH/models/VAE vae-ft-mse-840000-ema-pruned.ckpt

    #Install Dependencies
    sed_for installation $BASEPATH
    cd $BASEPATH && python launch.py --skip-torch-cuda-test && echo "Installation Completed" > $BASEPATH/.install_status
}

function run {
    #Install google perf tools
    install_perf_tools

    #Install pip dependencies
    pip install -q torch==2.0.0+cu118 torchvision==0.15.1+cu118 torchaudio==2.0.1+cu118 torchtext==0.15.1 torchdata==0.6.0 --extra-index-url https://download.pytorch.org/whl/cu118 -U
    pip install -q xformers==0.0.18 triton==2.0.0 -U

    #Prepare drive fusion MOVE THIS TOLATER
    mkdir /content/fused-models
    mkdir /content/models
    mkdir /content/fused-lora
    mkdir /content/lora
    unionfs-fuse $BASEPATH/models/Stable-diffusion=RW:/content/models=RW /content/fused-models
    unionfs-fuse $BASEPATH/extensions/sd-webui-additional-networks/models/lora=RW:$BASEPATH/models/Lora=RW:/content/lora=RW /content/fused-lora

    #Healthcheck and update all repos
    reset_repos $BASEPATH

    #Prepare for running
    sed_for run $BASEPATH

    #Make sure CLIP folder exists and downloads the model if not present
    mkdir -p $BASEPATH/models/CLIP
    safe_fetch https://openaipublic.azureedge.net/clip/models/b8cca3fd41ae0c99ba7e8951adf17d267cdb84cd88be6f7c2e0eca1737a03836/ViT-L-14.pt $BASEPATH/models/CLIP ViT-L-14.pt
 
    cd $BASEPATH
    python launch.py --listen --opt-sdp-attention --enable-insecure-extension-access --theme dark --gradio-queue --clip-models-path $BASEPATH/models/CLIP --multiple
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
apt -y update -qq && apt -y install -qq unionfs-fuse libcairo2-dev pkg-config python3-dev

if [ "$force" = true ] || [ ! -e "$BASEPATH/.install_status" ] || ! grep -qs "Installation Completed" "$BASEPATH/.install_status"; then
    install
fi

run
