#!/usr/bin/env bash
# Trains the #230 style LoRA, `sorcbobble`: the uniform huge-head caricature
# the owner picked (spike doc §7), learnt from our own picked SDXL renders so
# that plain SDXL-base txt2img can then paint any people x class x look in
# that one style, instead of each face being img2img'd off a template (§4.5).
#
# The training set is a folder of picked renders already cut out onto the one
# backdrop, each with its caption beside it — exactly what
# `gen_hero_portraits.py --matte` writes. The trainer is kohya's sd-scripts in
# its own venv (~/localgen/sd-scripts); the LoRA lands where ComfyUI reads
# LoRAs. Sized for the owner's 8 GB card: UNet only, fp8 base, cached latents
# and text-encoder outputs, gradient checkpointing, batch 1.
#
#     tools/localgen/train_hero_lora.sh ~/localgen/lora/sorcbobble/img
#
# ComfyUI holds ~5 GB of VRAM while it runs; stop it first.
set -euo pipefail
IMG=${1:?folder of picked, matted renders with .txt captions}
STEPS=${STEPS:-1500}
SD=~/localgen/sd-scripts
CKPT=~/localgen/ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors
OUT=~/localgen/ComfyUI/models/loras
CFG=$(mktemp --suffix .toml)
cat > "$CFG" <<EOF
[general]
caption_extension = ".txt"
keep_tokens = 1

[[datasets]]
resolution = 1024
batch_size = 1
enable_bucket = false

  [[datasets.subsets]]
  image_dir = "$IMG"
  num_repeats = 10
EOF
cd "$SD"
.venv/bin/python sdxl_train_network.py \
  --pretrained_model_name_or_path "$CKPT" --dataset_config "$CFG" \
  --output_dir "$OUT" --output_name sorcbobble --save_model_as safetensors \
  --network_module networks.lora --network_dim 16 --network_alpha 8 \
  --network_train_unet_only --cache_latents --cache_text_encoder_outputs \
  --gradient_checkpointing --mixed_precision bf16 --save_precision fp16 --fp8_base \
  --optimizer_type Adafactor --optimizer_args relative_step=False scale_parameter=False warmup_init=False \
  --learning_rate 1e-4 --lr_scheduler constant_with_warmup --lr_warmup_steps 100 \
  --max_train_steps "$STEPS" --save_every_n_steps 500 --sdpa --no_half_vae --seed 230
