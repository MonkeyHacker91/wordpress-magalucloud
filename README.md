# Magalu Cloud - Wordpress Installer

Instalador automatizado de WordPress para Ubuntu na Magalu Cloud.

Este projeto provisiona:

- Nginx otimizado para WordPress
- MariaDB com tuning automático por RAM
- PHP-FPM e extensões comuns do WordPress
- Configuração inicial de segurança e permissões
- SSL opcional com Certbot

## 1) Pré-requisitos

- Servidor Ubuntu com acesso SSH
- Domínio apontando para o IP do servidor (registro A)
- Usuário com permissão de `sudo`

### Máquina recomendada

- **RAM:** mínimo **2 GB**
- **vCPU:** 1 ou mais
- **Disco:** 20 GB ou mais (SSD recomendado)

## 2) Enviar arquivos para o GitHub

Se você quer versionar no seu repositório:

```bash
git add install.sh README.md
git commit -m "Adiciona instalador WordPress para Magalu Cloud e documentação"
git push origin main
```

## 3) Subir script para o servidor

No seu computador local:

```bash
scp -P 22 "install.sh" usuario@IP_DO_SERVIDOR:/tmp/
```

Exemplo:

```bash
scp -P 22 "install.sh" dominios1@186.227.194.205:/tmp/
```

## 4) Executar no servidor

Conecte por SSH:

```bash
ssh -p 22 usuario@IP_DO_SERVIDOR
```

Dê permissão e rode:

```bash
chmod +x /tmp/install.sh
sudo /tmp/install.sh --domain seu-dominio.com.br --certbot yes
```

## 5) Exemplo completo

```bash
sudo /tmp/install.sh \
  --domain meusite.com.br \
  --db-name wordpress \
  --db-user wordpressuser \
  --certbot yes
```

## 6) O que o script já faz

- Atualiza pacotes do sistema
- Instala e habilita Nginx/MariaDB/PHP
- Cria banco e usuário no MariaDB
- Aplica tuning de performance no MariaDB (auto-ajustado pela RAM)
- Baixa e configura WordPress
- Cria virtual host Nginx otimizado para WordPress
- Ajusta permissões de segurança
- Ativa SSL (se `--certbot yes`)

## 7) O que o script otimiza

### Nginx
- `try_files` correto para WordPress
- Cache de estáticos com `Cache-Control` e `expires`
- Bloqueio de `xmlrpc.php`, `wp-config.php`, arquivos ocultos e PHP em uploads
- Headers de segurança (`X-Frame-Options`, `X-Content-Type-Options`, etc)

### MariaDB
- Gera arquivo de tuning: `/etc/mysql/mariadb.conf.d/99-magalu-wordpress-optimized.cnf`
- Aplica parâmetros de performance (InnoDB/I-O/cache/conexões)
- Usa perfil alto para servidores grandes e autoajuste seguro para VPS menores

## 8) Onde ver logs

No servidor:

```bash
cat /var/log/wp-bootstrap.log
```

Ou acompanhar ao vivo:

```bash
tail -f /var/log/wp-bootstrap.log
```

## 9) Possíveis erros comuns

- **Domínio não abriu:** confirme DNS apontando para o IP correto.
- **SSL falhou:** geralmente DNS ainda não propagou.
- **Permissão negada:** execute com `sudo`.
- **Porta 80/443 bloqueada:** liberar firewall para HTTP/HTTPS.

## 10) Segurança básica pós-instalação

- Trocar senhas padrão do painel WordPress
- Remover plugins/temas não usados
- Manter servidor e WordPress atualizados
- Usar senha forte no banco (o script gera automaticamente se não passar `--db-pass`)

## 11) Comandos úteis

Ver status do Nginx:

```bash
sudo systemctl status nginx
```

Testar configuração do Nginx:

```bash
sudo nginx -t
```

Reiniciar Nginx:

```bash
sudo systemctl restart nginx
```
