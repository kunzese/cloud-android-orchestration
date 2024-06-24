# Steps

## Set up project

```
$ cd terraform
$ terraform plan
$ terraform apply
```

## Build and push the cloud orchestrator image

```
$ docker build -t us-central1.pkg.dev/kunzese-fast-demo-co-ko56/my-repository/cloud-orchestrator:latest .
$ docker push us-central1.pkg.dev/kunzese-fast-demo-co-ko56/my-repository/cloud-orchestrator:latest
```

## Patch Cloud Run service

```
$ gcloud run services update example \
    --region=us-central1 \
    --image=us-central1.pkg.dev/kunzese-fast-demo-co-ko56/my-repository/cloud-orchestrator:latest \
    --update-env-vars=IAP_AUDIENCE=/projects/525833519488/global/backendServices/2669782804217519149
```
