# Contexto: verificación en vivo de wazuh-kubernetes #1660

## Objetivo
Issue: https://github.com/wazuh/wazuh-kubernetes/issues/1660
PR (Draft, sin verificar en vivo todavía): #1688, rama `change/1660-adapt-credentials-process`,
base `5.0.0`.

Todo el trabajo de código y documentación ya está hecho y comiteado. Lo único que falta es
verificar en vivo que el despliegue funciona de extremo a extremo: pods arrancando, credenciales
resolviéndose bien, login real al dashboard, y confirmar si el clúster multi-réplica del indexer
forma correctamente (relacionado con wazuh-indexer#1916).

## Entorno
Una instancia AWS Ubuntu 24.04 x86_64 (`m-xlarge`), con MicroK8s instalado (v1.35.6), complementos
`dns` y `storage`/`hostpath-storage` activados. Alias SSH: `k8s-test`.

Dentro de la instancia: `~/wazuh-kubernetes/`, rama `change/1660-adapt-credentials-process` ya
clonada y actualizada. Dentro de `wazuh/`:
- `wazuh-certs-tool.sh` y `wazuh-credentials.sh` descargados (build dev, confirmado con `grep` que
  llevan la lógica de la épica).
- `config.yml` ya escrito con el formato `dns:` correcto (3 réplicas indexer, manager, dashboard).
- `certificates-conf.sh --cert --copy --priv` ya ejecutado sin errores.
- `credentials-conf.sh` ya ejecutado sin errores — las 5 contraseñas ya están generadas en
  `wazuh/config/credentials/{indexer,manager,dashboard}.env`.

**No repitas la generación de certificados/credenciales** — ya está hecha, y `credentials-conf.sh`
se niega a sobreescribir sin `--force` (comportamiento correcto, no lo fuerces).

## Lo que falta hacer, en orden
1. Desde `~/wazuh-kubernetes/`, aplicar el overlay local:
   `microk8s kubectl apply -k envs/local-env/`
   (usa `microk8s kubectl`, no `kubectl` a secas, salvo que el PATH ya tenga un alias —
   compruébalo primero con `which kubectl` y `microk8s.kubectl version` si hay dudas)
2. Esperar a que los pods lleguen a Ready:
   `microk8s kubectl -n wazuh wait --for=condition=Ready pod --all --timeout=600s`
3. Si algún pod no llega a Ready, diagnosticar con `describe` y `logs` antes de asumir nada — no
   reintentar a ciegas.
4. Verificar el login real:
   `grep '^WAZUH_INDEXER_ADMIN_PASSWORD=' config/credentials/indexer.env | cut -d= -f2-`
   y comprobar con curl (desde dentro de un pod, vía `kubectl exec`, o con port-forward) que
   autentica.
5. Ejecutar `tools/tests/check-default-credentials.sh` contra el despliegue real (necesita estar
   en `wazuh/`, ya que lee `./config/credentials/*.env` — ver su `--help`).
6. **Importante para el PR**: confirmar si los 3 pods del indexer forman clúster (mirar
   `cluster.initial_cluster_manager_nodes`, logs de descubrimiento, `_cluster/health` con
   `number_of_nodes: 3`). Esto resuelve la sección "Pending" del PR sobre wazuh-indexer#1916.

## Cosas ya confirmadas, no las vuelvas a cuestionar
- El fix de `runAsUser`/`runAsGroup` en `dashboard-deploy.yaml` e `indexer-sts.yaml` ya está
  aplicado y comiteado — confirmado necesario por Víctor Ereñú tras la review de Jota Molas en
  wazuh-docker#2699.
- `network.publish_host` en `indexer-sts.yaml` ya usa DNS por pod
  (`$(POD_NAME).wazuh-indexer.$(POD_NAMESPACE).svc.cluster.local`), no IP — es el mismo mecanismo
  que Docker aplicó para wazuh-indexer#1916. Falta confirmar en vivo que basta.
- Los 5 nombres de cuenta y sus claves: `WAZUH_INDEXER_ADMIN_PASSWORD` (admin),
  `WAZUH_INDEXER_KIBANASERVER_PASSWORD` (kibanaserver), `WAZUH_INDEXER_MANAGER_PASSWORD`
  (wazuh-manager), `WAZUH_MANAGER_API_PASSWORD` (wazuh), `WAZUH_MANAGER_WUI_PASSWORD` (wazuh-wui).

## Reglas de trabajo
- Nunca imprimir el contenido completo de los `.env` de credenciales en la salida ni en logs
  compartidos — usa `grep` de una clave concreta cuando haga falta un valor, no `cat` del fichero
  entero.
- Guarda la salida relevante de cada paso en `logs/<paso>.log` dentro de la instancia, para poder
  revisar después sin tener que repetir comandos.
- Si algo fallara de forma que sugiera que el problema está en el propio diseño (no en esta
  instancia concreta), dilo explícitamente distinguiendo "esto es un bug de nuestros manifiestos"
  de "esto es peculiar de MicroK8s y no se daría en EKS" — por ejemplo, cualquier cosa relacionada
  con LoadBalancer/Ingress de Traefik no aplica aquí, MicroK8s no tiene esa capa.
