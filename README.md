# Instalação Zabbix 7.0 LTS no Debian 13

Automatiza a instalação do Zabbix 7.0 LTS (Server, Frontend e Agent) no Debian 13 (Trixie), utilizando PostgreSQL como banco de dados e Nginx como servidor web — tudo na mesma máquina. O script cria o usuário e o banco no PostgreSQL, importa o schema inicial e ajusta as configurações essenciais do Zabbix Server, Agent e Nginx.

## Pré-requisitos
- Um servidor Debian 13 recém-instalado (acesso root ou sudo)
- Conexão com a internet (acesso aos repositórios Debian e Zabbix)
- Porta `8080` liberada (ou ajuste a porta no script)

## Como Usar
1. Clonar este repositório:
   ```bash
   git clone <URL_DO_SEU_REPOSITORIO_GITHUB>
   cd <PASTA_DO_REPOSITORIO>
   ```
2. Tornar o script executável:
   ```bash
   chmod +x install_zabbix_7.0.sh
   ```
3. Executar o instalador (opcionalmente informe a senha do banco via variável):
   ```bash
   # opção A: exportando a senha antes
   export ZBX_DB_PASS='sua-senha-segura'
   sudo ./install_zabbix_7.0.sh

   # opção B: sem variável; o script solicitará a senha interativamente
   sudo ./install_zabbix_7.0.sh
   ```

> Observação: o script configura o Nginx para escutar na porta `8080` com `server_name localhost`. Ajuste os valores nas variáveis `NGINX_LISTEN_PORT` e `SERVER_NAME` dentro do script, se necessário.

## Pós-Instalação
- Acesse o frontend do Zabbix em:
  - `http://ip-do-servidor:8080/` (padrão deste repositório)
  - Se alterar a porta para 80, use `http://ip-do-servidor/`
- Login padrão do frontend: `Admin` / `zabbix` (diferencia maiúsculas/minúsculas)
- No assistente do Zabbix (wizard), use:
  - Tipo de banco: `PostgreSQL`
  - Host: `localhost`
  - Porta: `0` (padrão) ou `5432`
  - Banco: `zabbix`
  - Usuário: `zabbix`
  - Senha: a definida durante a instalação (ou em `ZBX_DB_PASS`)
- Recomendações:
  - Altere a senha do usuário `Admin` imediatamente e, se possível, habilite 2FA
  - Ajuste `server_name` e crie o DNS/FQDN correspondente
  - Considere configurar HTTPS (Let’s Encrypt) e firewall (liberando a porta HTTP/HTTPS)

## Estrutura
- `install_zabbix_7.0.sh`: script de instalação automatizada
- `.gitignore`: ignora arquivos de log e configurações locais sensíveis
- `README.md`: este guia

## Solução de Problemas
- Verifique serviços e logs:
  ```bash
  systemctl status zabbix-server zabbix-agent nginx php8.4-fpm postgresql
  journalctl -u zabbix-server -e --no-pager
  journalctl -u nginx -e --no-pager
  journalctl -u postgresql -e --no-pager
  ```
- Se o frontend não abrir:
  - Confirme se a porta definida no Nginx está liberada no firewall
  - Valide `listen` e `server_name` em `/etc/zabbix/nginx.conf`
  - Reinicie Nginx e PHP-FPM: `sudo systemctl restart nginx php8.4-fpm`