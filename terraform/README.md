# Steps

## STEP 1: Set up project

```
$ cd terraform
$ terraform plan
$ terraform apply
```

`terraform apply` returns four outputs which you need to run after `terraform apply` ends successfully.

## STEP 2: Build and push the cloud orchestrator image

```
gcloud auth configure-docker \
    europe-west3-docker.pkg.dev
```

```
$ docker build -t europe-west3-docker.pkg.dev/[PROJECT_ID]/my-repository/cloud-orchestrator:latest .
$ docker push europe-west3-docker.pkg.dev/[PROJECT_ID]/my-repository/cloud-orchestrator:latest
```

## STEP 3: Patch Cloud Run service

```
$ gcloud run deploy cloud-orchestrator \
  --image=europe-west3-docker.pkg.dev/[PROJECT_ID]/my-repository/cloud-orchestrator:latest \
  --no-allow-unauthenticated \
  --port=8080 \
  --service-account=cloud-orchestrator@[PROJECT_ID].iam.gserviceaccount.com \
  --set-env-vars='CONFIG_FILE=/config/conf.toml' --set-env-vars='IAP_AUDIENCE=/projects/[PROJECT_NUMBER]/global/backendServices/327730686667727339' \
  --set-secrets=/config/conf.toml=cloud-orchestrator-config:latest \
  --ingress=internal-and-cloud-load-balancing \
  --vpc-connector=projects/[PROJECT_ID]/locations/europe-west3/connectors/co-vpc-connector \
  --vpc-egress=private-ranges-only \
  --region=europe-west3 \
  --project=[PROJECT_ID]
$ gcloud run services add-iam-policy-binding cloud-orchestrator --member=serviceAccount:service-[PROJECT_NUMBER]@gcp-sa-iap.iam.gserviceaccount.com --role=roles/run.invoker
```
