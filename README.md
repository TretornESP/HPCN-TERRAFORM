# HPCN-TERRAFORM

Este fichero ejecuta los test NPB en infraestructura de Azure, DigitalOcean y GCP mediante Terraform.

## Estructura de ficheros

- `run.sh`: Script que ejecuta los comandos de terraform y los test NPB. Por defecto instala terraform y genera la clave ssh.
- `*.tf`: Ficheros de configuración de terraform. Crea una red virtual, un grupo de seguridad, N máquinas virtuales y un disco compartido NFS, instala mange y slurm. Ademas comienza a ejecutar el test general.
- `reports`: Ficheros de resultados en bruto usados en la práctica.
- `analyze.py`: Un script simple que dados tiempos de ejecución, calcula el speedup y la eficiencia paralela.

## Requisitos

Una cuenta de Azure con permisos para crear recursos y la cloud shell habilitada.

## Pasos

1. Obtener las claves de acceso a Azure, el Api key de google cloud o el token de Digital Ocean

```bash
az login
# Nos mostrará un enlace para iniciar sesion en la web de Azure
# Una vez logueados nos mostrara el id de la suscripcion
az account set --subscription "SUBSCRIPTION_ID"
az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/SUBSCRIPTION_ID"
# Nos devolverá un JSON con los datos de la cuenta de servicio
```
```bash
gcloud auth application-default login
gcloud init
gcloud auth application-default login
```

2. Editar el fichero `run.sh` y añadir los datos de la cuenta de servicio si usas Azure

```bash
ARM_CLIENT_ID => appid
ARM_CLIENT_SECRET => password
ARM_SUBSCRIPTION_ID => subscription
ARM_TENANT_ID => tenant
```

Si usas DigitalOcean descomenta la línea e incluye tu API Key

```bash
echo digitalocean_token = "changeme" >> terraform.tfvars
```

3. Si necesitamos instalar algo más, podemos descomentar las líneas correspondientes, además
podemos generar la clave ssh necesaria para acceder a las máquinas virtuales. Por último renombramos
el fichero `.tf` necesario a `main.tf` y seleccionamos el usuario de operaciones

4. Ejecutar el script `run.sh` para crear la infraestructura.
Por seguridad nos pedira que introduzcamos 3 veces la clave ssh

5. Para ejecuciones posteriores podemos comentar las lineas señaladas del `run.sh`

6. A mayores del output en general, nos creara un fichero `report.tar.gz` en la carpeta actual

7. Para entrar en modo interactivo al nodo head ejecutamos:

```bash
ssh -i ~/.ssh/id_rsa $username@$(terraform output -raw head_public_ip_address)
```

7. Si entramos en modo interactivo antes del startup, debemos cargar el path con los binarios de slurm mediante el comando

```bash
source /etc/profile.d/slurm.sh
```

8. Para ejecutar las pruebas NPB, ejecutamos el comando

```bash
/home/$username/exec.sh
#Podemos comentar las lineas de ejecucion de los test que no queramos!
```

### referencias:
https://developer.hashicorp.com/terraform/tutorials/azure-get-started/azure-build
https://learn.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-terraform?tabs=azure-cli
https://www.youtube.com/watch?v=_45W3Z8XWL4
https://www.digitalocean.com/community/tutorials/how-to-use-terraform-with-digitalocean
https://cloud.google.com/docs/terraform?hl=es-419

## Datos en bruto:

do
[KERNEL: lu.B.x NODES: 1 TPN: 1 ITERATIONS: 5] AVG: 174.18400000000000000000
[KERNEL: lu.B.x NODES: 1 TPN: 2 ITERATIONS: 5] AVG: 102.17600000000000000000
[KERNEL: lu.B.x NODES: 2 TPN: 2 ITERATIONS: 5] AVG: 62.28600000000000000000
[KERNEL: lu.B.x NODES: 4 TPN: 2 ITERATIONS: 5] AVG: 37.91800000000000000000

[KERNEL: cg.B.x NODES: 1 TPN: 1 ITERATIONS: 5] AVG: 67.92200000000000000000
[KERNEL: cg.B.x NODES: 1 TPN: 2 ITERATIONS: 5] AVG: 30.22400000000000000000
[KERNEL: cg.B.x NODES: 2 TPN: 2 ITERATIONS: 5] AVG: 19.20800000000000000000
[KERNEL: cg.B.x NODES: 4 TPN: 2 ITERATIONS: 5] AVG: 18.25200000000000000000

cgp
[KERNEL: lu.B.x NODES: 1 TPN: 1 ITERATIONS: 5] AVG: 252.59000000000000000000
[KERNEL: lu.B.x NODES: 1 TPN: 2 ITERATIONS: 5] AVG: 193.28800000000000000000
[KERNEL: lu.B.x NODES: 2 TPN: 2 ITERATIONS: 5] AVG: 118.21000000000000000000
[KERNEL: lu.B.x NODES: 4 TPN: 2 ITERATIONS: 5] AVG: 98.51600000000000000000

[KERNEL: cg.B.x NODES: 1 TPN: 1 ITERATIONS: 5] AVG: 85.80000000000000000000
[KERNEL: cg.B.x NODES: 1 TPN: 2 ITERATIONS: 5] AVG: 72.83000000000000000000
[KERNEL: cg.B.x NODES: 2 TPN: 2 ITERATIONS: 5] AVG: 40.46600000000000000000
[KERNEL: cg.B.x NODES: 4 TPN: 2 ITERATIONS: 5] AVG: 13.73400000000000000000

azure
[KERNEL: lu.B.x NODES: 1 TPN: 1 ITERATIONS: 5] AVG: 154.91600000000000000000
[KERNEL: lu.B.x NODES: 1 TPN: 2 ITERATIONS: 5] AVG: 79.99000000000000000000
[KERNEL: lu.B.x NODES: 2 TPN: 2 ITERATIONS: 5] AVG: 42.31400000000000000000
[KERNEL: lu.B.x NODES: 4 TPN: 2 ITERATIONS: 5] AVG: 25.63000000000000000000

[KERNEL: cg.B.x NODES: 1 TPN: 1 ITERATIONS: 5] AVG: 46.41600000000000000000
[KERNEL: cg.B.x NODES: 1 TPN: 2 ITERATIONS: 5] AVG: 24.67600000000000000000
[KERNEL: cg.B.x NODES: 2 TPN: 2 ITERATIONS: 5] AVG: 20.58000000000000000000
[KERNEL: cg.B.x NODES: 4 TPN: 2 ITERATIONS: 5] AVG: 17.98800000000000000000


