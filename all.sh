#/bin/bash

function safe_git {
  if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: safe_git <repo_url> <local_folder> [<branch_name>]"
    return 1
  fi

  local repo_url=$1 local_folder=$2 branch_name=${3:-""} retry_count=3

  if [ -d "$local_folder/.git" ] && git -C "$local_folder" rev-parse &> /dev/null; then
    echo "INFO: Repo $local_folder is valid, performing update."
    git -C "$local_folder" pull && return 0
  else
    echo "INFO: Repo $local_folder is not valid or does not exist, cloning."
    rm -rf "$local_folder"
    for i in $(seq $retry_count); do
      git clone ${branch_name:+-b "$branch_name"} "$repo_url" "$local_folder" && return 0
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

env TF_CPP_MIN_LOG_LEVEL=1

sudo apt update
pip install -q torch==1.13.1+cu116 torchvision==0.14.1+cu116 torchaudio==0.13.1 torchtext==0.14.1 torchdata==0.5.1 --extra-index-url https://download.pytorch.org/whl/cu116 -U
pip install -q xformers==0.0.16 triton==2.0.0 -U

BASEPATH=/home/lang
safe_git https://github.com/camenduru/stable-diffusion-webui $BASEPATH/stable-diffusion-webui v2.1
safe_git https://huggingface.co/embed/negative $BASEPATH/stable-diffusion-webui/embeddings/negative
safe_git https://huggingface.co/embed/lora $BASEPATH/stable-diffusion-webui/models/Lora/positive
safe_fetch https://huggingface.co/embed/upscale/resolve/main/4x-UltraSharp.pth $BASEPATH/stable-diffusion-webui/models/ESRGAN 4x-UltraSharp.pth
safe_fetch https://raw.githubusercontent.com/camenduru/stable-diffusion-webui-scripts/main/run_n_times.py $BASEPATH/stable-diffusion-webui/scripts run_n_times.py
safe_git https://github.com/deforum-art/deforum-for-automatic1111-webui $BASEPATH/stable-diffusion-webui/extensions/deforum-for-automatic1111-webui
safe_git https://github.com/camenduru/stable-diffusion-webui-images-browser $BASEPATH/stable-diffusion-webui/extensions/stable-diffusion-webui-images-browser
safe_git https://github.com/camenduru/stable-diffusion-webui-huggingface $BASEPATH/stable-diffusion-webui/extensions/stable-diffusion-webui-huggingface
safe_git https://github.com/camenduru/sd-civitai-browser $BASEPATH/stable-diffusion-webui/extensions/sd-civitai-browser
safe_git https://github.com/kohya-ss/sd-webui-additional-networks $BASEPATH/stable-diffusion-webui/extensions/sd-webui-additional-networks
safe_git https://github.com/Mikubill/sd-webui-controlnet $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet
safe_git https://github.com/camenduru/openpose-editor $BASEPATH/stable-diffusion-webui/extensions/openpose-editor
safe_git https://github.com/jexom/sd-webui-depth-lib $BASEPATH/stable-diffusion-webui/extensions/sd-webui-depth-lib
safe_git https://github.com/hnmr293/posex $BASEPATH/stable-diffusion-webui/extensions/posex
safe_git https://github.com/camenduru/sd-webui-tunnels $BASEPATH/stable-diffusion-webui/extensions/sd-webui-tunnels
safe_git https://github.com/etherealxx/batchlinks-webui $BASEPATH/stable-diffusion-webui/extensions/batchlinks-webui
safe_git https://github.com/camenduru/stable-diffusion-webui-catppuccin $BASEPATH/stable-diffusion-webui/extensions/stable-diffusion-webui-catppuccin
safe_git https://github.com/KohakuBlueleaf/a1111-sd-webui-locon $BASEPATH/stable-diffusion-webui/extensions/a1111-sd-webui-locon
safe_git https://github.com/AUTOMATIC1111/stable-diffusion-webui-rembg $BASEPATH/stable-diffusion-webui/extensions/stable-diffusion-webui-rembg
safe_git https://github.com/ashen-sensored/stable-diffusion-webui-two-shot $BASEPATH/stable-diffusion-webui/extensions/stable-diffusion-webui-two-shot
safe_git https://github.com/camenduru/sd_webui_stealth_pnginfo $BASEPATH/stable-diffusion-webui/extensions/sd_webui_stealth_pnginfo
cd $BASEPATH/stable-diffusion-webui
git reset --hard

safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/control_canny-fp16.safetensors $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models control_canny-fp16.safetensors
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/control_depth-fp16.safetensors $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models control_depth-fp16.safetensors
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/control_hed-fp16.safetensors $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models control_hed-fp16.safetensors
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/control_mlsd-fp16.safetensors $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models control_mlsd-fp16.safetensors
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/control_normal-fp16.safetensors $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models control_normal-fp16.safetensors
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/control_openpose-fp16.safetensors $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models control_openpose-fp16.safetensors
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/control_scribble-fp16.safetensors $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models control_scribble-fp16.safetensors
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/control_seg-fp16.safetensors $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models control_seg-fp16.safetensors
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/hand_pose_model.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/annotator/openpose hand_pose_model.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/body_pose_model.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/annotator/openpose ody_pose_model.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/dpt_hybrid-midas-501f0c75.pt $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/annotator/midas dpt_hybrid-midas-501f0c75.pt
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/mlsd_large_512_fp32.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/annotator/mlsd mlsd_large_512_fp32.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/mlsd_tiny_512_fp32.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/annotator/mlsd mlsd_tiny_512_fp32.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/network-bsds500.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/annotator/hed network-bsds500.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/upernet_global_small.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/annotator/uniformer upernet_global_small.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/t2iadapter_style_sd14v1.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models t2iadapter_style_sd14v1.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/t2iadapter_sketch_sd14v1.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models t2iadapter_sketch_sd14v1.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/t2iadapter_seg_sd14v1.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models t2iadapter_seg_sd14v1.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/t2iadapter_openpose_sd14v1.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models t2iadapter_openpose_sd14v1.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/t2iadapter_keypose_sd14v1.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models t2iadapter_keypose_sd14v1.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/t2iadapter_depth_sd14v1.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models t2iadapter_depth_sd14v1.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/t2iadapter_color_sd14v1.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models t2iadapter_color_sd14v1.pth
safe_fetch https://huggingface.co/ckpt/ControlNet/resolve/main/t2iadapter_canny_sd14v1.pth $BASEPATH/stable-diffusion-webui/extensions/sd-webui-controlnet/models t2iadapter_canny_sd14v1.pth

safe_fetch https://huggingface.co/ckpt/sd15/resolve/main/v1-5-pruned-emaonly.ckpt $BASEPATH/stable-diffusion-webui/models/Stable-diffusion v1-5-pruned-emaonly.ckpt

sed -i -e """/    prepare_environment()/a\    os.system\(f\'''sed -i -e ''\"s/dict()))/dict())).cuda()/g\"'' $BASEPATH/stable-diffusion-webui/repositories/stable-diffusion-stability-ai/ldm/util.py''')""" $BASEPATH/stable-diffusion-webui/launch.py
sed -i -e 's/fastapi==0.90.1/fastapi==0.89.1/g' $BASEPATH/stable-diffusion-webui/requirements_versions.txt

mkdir $BASEPATH/stable-diffusion-webui/extensions/deforum-for-automatic1111-webui/models

sed -i -e 's/\"sd_model_checkpoint\"\,/\"sd_model_checkpoint\,sd_vae\,CLIP_stop_at_last_layers\"\,/g' $BASEPATH/stable-diffusion-webui/modules/shared.py

python3 launch.py --listen --xformers --enable-insecure-extension-access --theme dark --gradio-queue --multiple
