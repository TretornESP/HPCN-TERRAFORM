# HPCN-TERRAFORM

Este fichero ejecuta los test NPB en infraestructura de Azure mediante Terraform.

## Estructura de ficheros

- `runner.sh`: Script que ejecuta los comandos de terraform y los test NPB. Por defecto instala terraform y genera la clave ssh.
- `main.tf`: Fichero de configuración de terraform. Crea una red virtual, un grupo de seguridad, N máquinas virtuales y un disco compartido NFS, instala mange y slurm. Ademas comienza a ejecutar el test general.
- `reports`: Ficheros de resultados en bruto usados en la práctica.

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

4. Para ejecuciones posteriores podemos comentar las lineas señaladas del runner.sh

5. A mayores del output en general, nos creara un fichero report.txt en la carpeta actual

6. Para entrar en modo interactivo al nodo head ejecutamos:

```bash
ssh -i ~/.ssh/id_rsa azureuser@$(terraform output -raw head_public_ip_address)
```

7. Si entramos en modo interactivo antes del startup, debemos cargar el path con los binarios de slurm mediante el comando

```bash
source /etc/profile.d/slurm.sh
```

8. Para ejecutar las pruebas NPB, ejecutamos el comando

```bash
/home/azureuser/exec.sh
#Podemos comentar las lineas de ejecucion de los test que no queramos!
```

## TODO

1. Añadir configuración dinámica tal y cómo en el script de cloudformation.
2. Añadir provider de Google Cloud
3. Añadir provider de Digital Ocean
4. Toma de datos de ejemplo y redacción de la memoria

### referencias:
https://developer.hashicorp.com/terraform/tutorials/azure-get-started/azure-build
https://learn.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-terraform?tabs=azure-cli
https://www.youtube.com/watch?v=_45W3Z8XWL4