"""
The main serverless worker module for runpod
"""

import json
import os
import runpod

import comftroller
import uploader
import utils

LOG_JOB_OUTPUTS = True

LOAD_IMAGE_NODE_ID = "68"   # LoadImage node in your workflow
KSAMPLER_NODE_ID   = "4"    # KSampler node in your workflow

def handler(job):
    job_input = job.get("input")
    if not isinstance(job_input, dict):
        return utils.error("no 'input' property found on job data")

    # Load workflow (optional override)
    workflow_in = job_input.get("workflow")
    if workflow_in is None:
        with open("/src/workflows/workflow_api.json", "r", encoding="utf-8") as f:
            workflow = json.load(f)
    else:
        workflow = utils.validate_json(workflow_in)
        if workflow is None:
            return utils.error("'workflow' must be a valid JSON object or JSON-encoded string")

    # Require exactly 1 input image
    input_files = job_input.get("files", [])
    if not isinstance(input_files, list) or len(input_files) != 1:
        return utils.error("Send exactly 1 image in input.files")

    # Require seed from request
    if "seed" not in job_input:
        return utils.error("Missing required input.seed")
    try:
        seed = int(job_input["seed"])
    except Exception:
        return utils.error("input.seed must be an integer")

    # Map image + seed into workflow
    # LoadImage expects just the filename that exists in ComfyUI input folder
    img_name = os.path.basename(input_files[0])

    try:
        workflow[LOAD_IMAGE_NODE_ID]["inputs"]["image"] = img_name
    except Exception as e:
        return utils.error(f"Workflow is missing LoadImage node {LOAD_IMAGE_NODE_ID} or its inputs.image field: {e}")

    try:
        workflow[KSAMPLER_NODE_ID]["inputs"]["seed"] = seed
    except Exception as e:
        return utils.error(f"Workflow is missing KSampler node {KSAMPLER_NODE_ID} or its inputs.seed field: {e}")

    # Optional: allow overriding some params if you want later
    # if "steps" in job_input: workflow[KSAMPLER_NODE_ID]["inputs"]["steps"] = int(job_input["steps"])
    # if "denoise" in job_input: workflow[KSAMPLER_NODE_ID]["inputs"]["denoise"] = float(job_input["denoise"])

    bucket_creds = None
    custom_aws = utils.validate_json(job_input.get("tobucket"))
    if custom_aws is not None:
        utils.log("will attempt to use 'tobucket' credentials from job input for aws upload")
        bucket_creds = custom_aws

    update_progress = lambda data: runpod.serverless.progress_update(job, data)

    outputs = comftroller.run(workflow, input_files, update_progress)

    if LOG_JOB_OUTPUTS:
        utils.log("---- RAW OUTPUTS ----")
        utils.log(outputs)
        utils.log("")

    if outputs.get("error"):
        return outputs.get("error")

    output_files = []
    output_datas = {}

    for node_id, node_output in outputs.items():
        if not any(key in node_output for key in ["images", "gifs"]):
            output_datas[node_id] = outputs[node_id]

        for key in ["images", "gifs"]:
            if key in node_output:
                for data in node_output[key]:
                    if data.get("type") == "output":
                        base = comftroller.GENERATION_OUTPUT_PATH
                        path = data["subfolder"] + data["filename"]
                        output_files.append(f"{base}/{path}")

    utils.log(f"#files generated: {len(output_files)}")

    for outfile in output_files:
        if not os.path.exists(outfile):
            return utils.error(f"couldn't locate output file: {outfile}")

    update_progress({"saving-image-data": True})

    aws_uploaded, bucket_urls = uploader.send_to_aws(output_files, "generations", bucket_creds)

    job_result = {"files": bucket_urls, "datas": output_datas}

    if (not aws_uploaded) and utils.job_prop_to_bool(job_input, "tobase64"):
        for index, local_file in enumerate(bucket_urls):
            job_result["files"][index] = utils.base64_encode(local_file)

    return job_result

runpod.serverless.start({"handler": handler})
