# HPCN-TERRAFORM

Este fichero ejecuta los test NPB en infraestructura de Azure mediante Terraform.

## Requisitos

Una cuenta de Azure con permisos para crear recursos y la cloud shell habilitada.

## Pasos

1. Obtener las claves de acceso a Azure.

```bash
az login
# Nos mostrará un enlace para iniciar sesion en la web de Azure
# Una vez logueados nos mostrara el id de la suscripcion
az account set --subscription "SUBSCRIPTION_ID"
az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/SUBSCRIPTION_ID"
# Nos devolverá un JSON con los datos de la cuenta de servicio
```

2. Editar el fichero `runner.sh` y añadir los datos de la cuenta de servicio.

```bash
ARM_CLIENT_ID => appid
ARM_CLIENT_SECRET => password
ARM_SUBSCRIPTION_ID => subscription
ARM_TENANT_ID => tenant
```

3. Ejecutar el script `runner.sh` para crear la infraestructura.
Por seguridad nos pedira que introduzcamos 3 veces la clave ssh

4. Para ejecuciones posteriores podemos comentar las lineas del runner para hacerlo idempotente.
```bash
#terraform init
#ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N $password 
```

5. A mayores del output en general, nos creara un fichero report.txt en la carpeta actual

## TODO

1. Añadir configuración dinámica tal y cómo en el script de cloudformation.
2. Añadir provider de Google Cloud
3. Añadir provider de Digital Ocean
4. Toma de datos de ejemplo y redacción de la memoria

### referencias:
https://developer.hashicorp.com/terraform/tutorials/azure-get-started/azure-build
https://learn.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-terraform?tabs=azure-cli
https://www.youtube.com/watch?v=_45W3Z8XWL4