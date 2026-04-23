# Guia Rápido (Leigos): Instalar WordPress na Magalu Cloud

Este guia usa o script `wpinstall_magalucloud.sh` para instalar:

- Nginx
- MySQL
- PHP
- WordPress
- (Opcional) SSL com Certbot

## 1) Pré-requisitos

- Servidor Ubuntu com acesso SSH
- Domínio apontando para o IP do servidor (registro A)
- Usuário com permissão de `sudo`

## 2) Enviar arquivos para o GitHub

Se você quer versionar no seu repositório:

```bash
git add wpinstall_magalucloud.sh GUIA_WPINSTALL_MAGALUCLOUD.md
git commit -m "Adiciona instalador WordPress para Magalu Cloud e guia para iniciantes"
git push origin main
```

## 3) Subir script para o servidor

No seu computador local:

```bash
scp -P 22 "wpinstall_magalucloud.sh" usuario@IP_DO_SERVIDOR:/tmp/
```

Exemplo:

```bash
scp -P 22 "wpinstall_magalucloud.sh" dominios1@186.227.194.205:/tmp/
```

## 4) Executar no servidor

Conecte por SSH:

```bash
ssh -p 22 usuario@IP_DO_SERVIDOR
```

Dê permissão e rode:

```bash
chmod +x /tmp/wpinstall_magalucloud.sh
sudo /tmp/wpinstall_magalucloud.sh --domain seu-dominio.com.br --certbot yes
```

## 5) Exemplo pronto para copiar

```bash
sudo /tmp/wpinstall_magalucloud.sh --domain meusite.com.br --db-name wordpress --db-user wordpressuser --certbot yes
```

## 6) O que o script já faz

- Atualiza pacotes do sistema
- Instala e habilita Nginx/MySQL/PHP
- Cria banco e usuário no MySQL
- Baixa e configura WordPress
- Cria virtual host Nginx
- Ajusta permissões de segurança
- Ativa SSL (se `--certbot yes`)

## 7) Onde ver logs

No servidor:

```bash
cat /var/log/wp-bootstrap.log
```

Ou acompanhar ao vivo:

```bash
tail -f /var/log/wp-bootstrap.log
```

## 8) Possíveis erros comuns

- **Domínio não abriu:** confirme DNS apontando para o IP correto.
- **SSL falhou:** geralmente DNS ainda não propagou.
- **Permissão negada:** execute com `sudo`.
- **Porta 80 bloqueada:** liberar firewall para HTTP/HTTPS.

## 9) Segurança básica pós-instalação

- Trocar senhas padrão do painel WordPress
- Remover plugins/temas não usados
- Manter servidor e WordPress atualizados
- Usar senha forte no banco (o script gera automaticamente se não passar `--db-pass`)

## 10) Comandos úteis

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
