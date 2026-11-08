# Todo-API från lokal app till G-demo

Den här guiden är en körordning för G-delen av examinationen. Filerna i repot förbereder installationen. G-momenten behöver också genomföras på en riktig EC2-instans och förklaras av båda i videon. AWS-region, instanstyp, Elastic IP och era aktuella publika IP-adresser väljs av er i AWS-konsolen. Inga AWS-resurser skapas av att läsa guiden eller köra appen lokalt.

Vi använder Ubuntu Server 24.04 LTS, PostgreSQL på samma server, systemd och Nginx. HTTP-anrop går till Nginx på port 80, vidare till Uvicorn/FastAPI på `127.0.0.1:8000` och därifrån till PostgreSQL på `127.0.0.1:5432`. API-processen körs som systemanvändaren `api` och projektet ligger i `/home/api/todo-api`.

**1. Gör förberedelserna före inspelningen**

- Acceptera Classroom-inbjudan, kontrollera teamet om två och skriv in gruppen i kursdokumentet.
- Kontrollera deadline och hur videolänken ska lämnas in på Discord och läroportalen.
- Kör igenom det lokala flödet i `readme.md`. Prova skapa, läsa, ändra och ta bort en uppgift. Kontrollera felaktig indata och att sparad data finns kvar efter API-omstart.
- Läs igenom skripten, tjänstefilen, Nginx-filen och cron-filen. Båda ska kunna förklara de kommandon ni visar.
- Kontrollera att den färdiga koden och driftsättningsfilerna finns på branchen `Tadios` i det repo som servern ska klona. Lokala filer når inte servern genom `git clone` förrän de har committats och pushats av er.
- Bestäm hur servern får läsa ert GitHub-repo. För ett privat Classroom-repo kan en administratör behöva lägga till en deploy key. Öva den valda metoden före inspelningen.
- Förbered en Discord-webhook för er egen server om ni använder notifieringarna här. Webhook-adressen och databaslösenordet hålls utanför Git och den synliga inspelningen.
- Gör en repetition från en helt ny instans och mät tiden. Installationen hämtar paket från internet, vilket gör att tidsåtgången kan variera.

Använd kommandoblocken som stöd och kör en rad i taget. Under inspelningen navigerar ni själva med `cd`, visar var ni står med `pwd`, tittar med `ls` och öppnar konfigurationsfiler i `nano`. Förberedda konfigurationsblock får klistras in i den öppnade editorn. Förklara vad ni ändrar medan ni gör det.

**2. Skapa en ny EC2-instans under inspelningen**

Öppna EC2 i AWS-konsolen och välj er region. Starta `Launch instance`, namnge instansen och välj Canonicals Ubuntu Server 24.04 LTS för x86-64. Välj en liten instanstyp och EBS-lagring som är berättigade enligt just ert kontos aktuella Free Tier-villkor. Kontrollera sammanfattningen innan ni startar. Anteckna region och instans-id för att kunna identifiera rätt instans senare. [AWS om att starta EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EC2_GetStarted.html)

Uppgiftens formulering om Free Tier innebär att ni behöver kontrollera kontots villkor i AWS. AWS skiljer mellan konton skapade före respektive från den 15 juli 2025. Berättigade instanstyper, tidsgränser och kreditvillkor varierar mellan dessa upplägg. Välj utifrån informationen i ert konto. [AWS om EC2 och Free Tier](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html)

Skapa också ett nytt nyckelpar under inspelningen och välj formatet `.pem` för OpenSSH. På dator A sparar ni den nedladdade privata nyckeln som `todo-demo-a.pem` i er användares `.ssh`-mapp, exempelvis `C:\Users\tiddi\.ssh\todo-demo-a.pem`. Skapa mappen om den saknas. Nyckeln ligger därmed utanför projektets Git-repo. Den privata nyckeln används för att bevisa er identitet. Servern har motsvarande publika nyckel. [AWS om nyckelpar](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-key-pairs.html)

Konfigurera security group med dessa inkommande regler. Ersätt adresserna med datorernas aktuella publika IPv4-adresser. Om ni sitter på samma nät kan båda använda samma publika adress.

| Protokoll och port | Källa | Användning |
|---|---|---|
| TCP 22 | Dator A:s publika IP med `/32` | SSH från dator A |
| TCP 22 | Dator B:s publika IP med `/32` | SSH från dator B |
| TCP 80 | `0.0.0.0/0` | Visa API:t över HTTP |

Security group styr vilken trafik som får nå instansen. G-demonstrationen använder port 80 för besökare och begränsar SSH till era datorer. API-porten 8000 och databasporten 5432 behöver ingen inkommande regel eftersom de används lokalt inne på servern. [AWS om regler för webb och SSH](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/security-group-rules-reference.html)

**3. Tilldela och koppla en Elastic IP**

Gå till `Network & Security` och `Elastic IPs` i samma region. Välj `Allocate Elastic IP address`, välj adressen och använd `Associate Elastic IP address` för den nya instansen. Använd därefter denna adress i SSH och webbläsaren. I resten av guiden betyder `DIN_ELASTIC_IP` just den adressen. En Elastic IP är en statisk publik IPv4-adress som tillhör kontot tills ni släpper den. AWS debiterar Elastic IP-adresser både när de används och när de ligger lediga. [AWS om Elastic IP](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html)

Vänta tills instansen är igång och dess statuskontroller har gått igenom. Ubuntu använder normalt inloggningsnamnet `ubuntu`. Kontrollera att port 22 tillåts från den dator som ansluter. [AWS om SSH-anslutning](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-to-linux-instance.html)

**4. Anslut och ge båda datorerna åtkomst**

På dator A öppnar ni PowerShell. Nyckelsökvägen nedan använder den inloggade Windows-användarens `.ssh`-mapp och fungerar oavsett vilken mapp terminalen står i. Byt `DIN_ELASTIC_IP` mot instansens Elastic IP.

```powershell
ssh -i "$env:USERPROFILE\.ssh\todo-demo-a.pem" ubuntu@DIN_ELASTIC_IP
```

När SSH frågar om serverns identitet kontrollerar ni att ni ansluter till er nya instans. AWS beskriver hur serverns fingerprint kan hämtas och kontrolleras. [AWS om SSH-klienten](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-to-linux-instance.html)

På dator B skapar ni en egen nyckel. Välj ett nytt filnamn för projektet och en lösenfras när ni får frågan. Den här privata nyckeln stannar på dator B.

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\todo-demo-b"
Get-Content "$env:USERPROFILE\.ssh\todo-demo-b.pub"
```

För över innehållet i den publika `.pub`-filen till dator A. I den öppna SSH-sessionen på dator A navigerar ni till SSH-katalogen och öppnar filen.

```bash
cd ~/.ssh
pwd
ls -la
nano authorized_keys
```

Lägg dator B:s publika nyckel på en egen rad under den befintliga nyckeln. Spara med `Ctrl+O`, bekräfta filnamnet med Enter och avsluta med `Ctrl+X`. Behåll dator A:s befintliga nyckel så att båda kan logga in. Kontrollera rättigheterna och testa sedan dator B i en separat terminal. [AWS om att lägga till en publik nyckel](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/replacing-key-pair.html)

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

```powershell
ssh -i "$env:USERPROFILE\.ssh\todo-demo-b" ubuntu@DIN_ELASTIC_IP
```

Båda visar `whoami` och `hostname` efter inloggning. Ni ska se samma server. Om nätverket byts behöver SSH-reglerna uppdateras med den nya publika IP-adressen.

**5. För över och kör grundinstallationen**

Öppna en lokal PowerShell-terminal i projektmappen på dator A. Den här raden körs på er dator och kopierar installationsskriptet till `ubuntu`-användarens hemkatalog på servern.

```powershell
scp -i "$env:USERPROFILE\.ssh\todo-demo-a.pem" .\scripts\setup-server.sh ubuntu@DIN_ELASTIC_IP:~/setup-server.sh
```

På servern öppnar ni skriptet och förklarar dess viktigaste delar innan ni kör det. `sudo` ger administratörsrättigheter för just kommandot. Grundinstallationen installerar paket, skapar användaren `api`, förbereder kataloger och lägger till alias.

```bash
cd ~
ls
nano setup-server.sh
sudo install -o root -g root -m 0700 setup-server.sh /root/todo-api-setup-server
sudo bash /root/todo-api-setup-server
id api
ls -ld /home/api
```

Användaren `ubuntu` används för administration via SSH. Användaren `api` kör själva applikationen med avgränsade rättigheter och behöver ingen egen SSH-inloggning. `sudo -u api` låter administratören köra ett enstaka kommando som applikationsanvändaren.

**6. Klona repot till api-användarens hemkatalog**

För ett privat GitHub-repo använder ni den åtkomstmetod som ni redan har övat och har rätt att använda. Följande exempel använder en läsbehörig deploy key som gäller ett enda repo. Nyckeln är separat från nycklarna ni använder för att logga in på EC2. [GitHub om deploy keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys)

```bash
sudo install -d -o api -g api -m 0700 /home/api/.ssh
sudo -u api ssh-keygen -t ed25519 -f /home/api/.ssh/github_todo -N '' -C todo-api-deploy
sudo cat /home/api/.ssh/github_todo.pub
```

En person med rätt behörighet lägger den publika nyckeln i det aktuella repots `Settings` och `Deploy keys`. Ge läsbehörighet. När GitHub efterfrågar verifiering av värdnyckeln jämför ni med GitHubs publicerade fingerprints. Den privata filen visas och kopieras inte. [GitHub om värdnycklar](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)

```bash
sudo -u api git -c 'core.sshCommand=ssh -i /home/api/.ssh/github_todo -o IdentitiesOnly=yes' clone --branch Tadios git@github.com:classroom-ua/mlo26-linux-hemtenta-tadios-and-tobias.git /home/api/todo-api
sudo -u api git -C /home/api/todo-api config core.sshCommand 'ssh -i /home/api/.ssh/github_todo -o IdentitiesOnly=yes'
cd /home/api/todo-api
pwd
ls
```

Om organisationen inte tillåter deploy keys behöver ni använda en annan godkänd kloningsmetod med befintlig repoåtkomst. Lös åtkomsten före inspelningen så att ni kan genomföra kloningen inom tidsgränsen.

**7. Skapa Python-miljön och konfigurera databasen**

Skapa miljön och installera paket som `api`. Den virtuella miljön gör att API:t får egna Python-paket. Serverns tjänst använder samma miljö genom en absolut sökväg.

```bash
sudo -u api python3 -m venv /home/api/todo-api/venv
sudo -u api /home/api/todo-api/venv/bin/python -m pip install -r /home/api/todo-api/requirements.txt
```

Databasen heter `todo_db` och appens databasroll heter `todo_api`. Rollen används för appens vanliga databasarbete. PostgreSQLs administrativa roll `postgres` används när databasen och behörigheterna skapas. Ubuntu beskriver både lokal autentisering och lösenordsbaserade anslutningar i sin PostgreSQL-guide. [Ubuntu om PostgreSQL](https://ubuntu.com/server/docs/how-to/databases/install-postgresql/)

Installationsskriptet för databasen frågar efter ett lösenord utan att skriva ut det. Det skapar `/etc/todo-api/api.env` och återanvänder den befintliga konfigurationen vid en omkörning. Filen ägs av root med rättigheten `0600`. Systemd läser den när appen startas. Exempelfilen `deploy/api.env.example` visar vilka fält som behövs.

```bash
cd /home/api/todo-api/scripts
ls
sudo nano setup-database.sh
sudo install -o root -g root -m 0700 setup-database.sh /root/todo-api-setup-database
sudo bash /root/todo-api-setup-database
sudo stat -c '%U %G %a %n' /etc/todo-api/api.env
```

Visa att filen ägs av root och har rättigheten `600` utan att skriva ut lösenordet. När skriptet är klart finns databasen och rollen. Tabellen initieras av installationssteget nedan med appens egna databasrättigheter.

**8. Installera systemd, Nginx och cron**

Systemd startar Uvicorn som användaren `api`, använder projektmappen som arbetskatalog och håller tjänsten igång enligt inställningarna i `deploy/todo-api.service`. Startkommandot använder `app:app`, vilket betyder FastAPI-objektet `app` i filen `app.py`. Tjänsten lyssnar på loopback-adressen `127.0.0.1:8000`. [Ubuntu om systemd-tjänster](https://manpages.ubuntu.com/manpages/noble/man5/systemd.service.5.html)

Nginx tar emot HTTP på port 80 och skickar anropen vidare till Uvicorn. Konfigurationen finns förberedd i `deploy/nginx-todo-api.conf`. Den installeras i `/etc/nginx/sites-available/todo-api` och aktiveras via `sites-enabled`. [Ubuntu om Nginx](https://ubuntu.com/server/docs/how-to/web-services/install-nginx/)

Under inspelningen navigerar ni själva till Nginx-katalogen och öppnar den nya konfigurationsfilen. Klistra in innehållet från repots `deploy/nginx-todo-api.conf`, förklara porten och `proxy_pass`, spara och avsluta. Gör detta före installationskommandot. Installationsskriptet bevarar en redan skapad konfiguration för just denna site.

```bash
cd /etc/nginx/sites-available
pwd
ls
sudo nano todo-api
```

Granska också den förberedda tjänstefilen och skriptet som installerar den. `install` ger de skyddade kopiorna rätt ägare och filrättigheter. När ni kör skriptet får det projektets sökväg som argument.

```bash
cd /home/api/todo-api/deploy
sudo nano todo-api.service
cd ../scripts
sudo nano install-config.sh
sudo install -o root -g root -m 0700 install-config.sh /root/todo-api-install-config
sudo bash /root/todo-api-install-config /home/api/todo-api
```

Installationsskriptet initierar tabellen, installerar tjänsten och de schemalagda skripten som root-ägda filer, laddar om systemds konfiguration och aktiverar tjänsterna. Det kontrollerar Nginx-konfigurationen innan webbplatsen tas i bruk. Visa sedan den installerade tjänstefilen och kontrollera Nginx.

```bash
cd /etc/systemd/system
sudo nano todo-api.service
sudo nginx -t
sudo systemctl status nginx --no-pager
```

Om ni senare ändrar tjänstefilen kör ni `sudo systemctl daemon-reload` följt av `sudo systemctl restart todo-api`. Om ni ändrar Nginx-filen kör ni `sudo nginx -t` och laddar därefter om med `sudo systemctl reload nginx` när kontrollen har lyckats.

**9. Kontrollera hela API-flödet**

Kontrollera tjänsten, de senaste loggarna och båda HTTP-lagren på servern.

```bash
sudo systemctl status todo-api --no-pager
sudo systemctl is-enabled todo-api
sudo journalctl -u todo-api -n 30 --no-pager
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1/ready
```

`systemctl status` visar tjänstens aktuella läge. `is-enabled` kontrollerar om tjänsten är aktiverad för start vid uppstart. `journalctl -u todo-api` filtrerar loggen till den egna tjänsten. [Ubuntu om systemctl](https://manpages.ubuntu.com/manpages/noble/man1/systemctl.1.html), [Ubuntu om journalctl](https://manpages.ubuntu.com/manpages/noble/man1/journalctl.1.html)

Öppna `http://DIN_ELASTIC_IP/docs` i webbläsaren på er dator och genomför följande i Swagger.

1. Skapa en uppgift med `POST /Todo` och spara dess id.
2. Visa uppgiften med `GET /Todo/{todo_id}` och i `GET /Todo/list`.
3. Ändra titel och markera uppgiften som klar med `PATCH /Todo/{todo_id}`.
4. Starta om API:t med kommandot nedan och hämta samma uppgift igen.
5. Radera uppgiften med `DELETE /Todo/{todo_id}`. Visa att en efterföljande hämtning ger 404.

```bash
sudo systemctl restart todo-api
```

Logga ut ur en SSH-session och visa att `/docs` fortfarande fungerar. API:t körs nu som en systemtjänst. Vid repetitionen kan ni också starta om hela instansen och kontrollera att tjänsten och databasen återkommer.

**10. Kör backup och verifiera innehållet**

Backupskriptet körs som root och använder PostgreSQLs lokala administratörsåtkomst för att skapa en databasbackup. Det sparar även loggar under `/var/backups/todo-api`. Databasdumpen kan användas för återläsning. `pg_dump` exporterar en databas och tar en konsekvent ögonblicksbild även när appen används. [PostgreSQL om pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html)

```bash
sudo /usr/local/sbin/todo-api-backup
sudo ls -lh /var/backups/todo-api
```

Visa vilken fil som är databasdumpen och vilken som innehåller loggar. Förklara varför en kopia av PostgreSQLs levande datakatalog inte ersätter en kontrollerad databasdump. Öva även återläsning till en separat testdatabas före inspelningen. Backupen som uppgiften kräver ligger på EC2, vilket innebär att den delar instansens lagring med originaldata.

Använd det faktiska filnamnet från listningen i följande kontroll. `pg_restore --list` visar dumpens innehåll och `tar -tzf` listar loggarkivet.

```bash
sudo pg_restore --list /var/backups/todo-api/VALD_BACKUP.dump
sudo tar -tzf /var/backups/todo-api/VALT_LOGGARKIV.tar.gz
```

Vid repetitionen kan ni återläsa till en ny, separat testdatabas och kontrollera antal uppgifter. Ersätt backupfilnamnet och välj ett testdatabasnamn som är ledigt. Produktionsdatabasen `todo_db` används inte som mål för det här provet.

```bash
sudo -u postgres createdb todo_restore_check
sudo cat /var/backups/todo-api/VALD_BACKUP.dump | sudo -u postgres pg_restore --no-owner --no-privileges --dbname=todo_restore_check
sudo -u postgres psql --dbname=todo_restore_check --command='SELECT count(*) FROM todos'
```

**11. Konfigurera och testa övervakningen**

Övervakningen använder `/ready` för att kontrollera API:t och dess databasåtkomst. Den kontrollerar också diskutrymmet och larmar när användningen når den konfigurerade gränsen, som är 80 procent i exemplet. Inställningarna ligger i `/etc/todo-api/monitor.env`.

Öppna `deploy/monitor.env.example` för att läsa vilka värden som behövs. Installationsskriptet har redan skapat den riktiga filen med root som ägare och rättigheten `0600`. Redigera den befintliga filen så att en sparad webhook bevaras vid omkörning. Katalogen `/etc/todo-api` kräver rootåtkomst, så öppna först en administratörssession med `sudo -i`. Fyll i den egna webhook-adressen med inspelningen skyddad från att visa hemligheten. Kontrollera rättigheter med `stat`, utan att skriva ut filinnehållet, och lämna sedan administratörssessionen med `exit`.

```bash
sudo -i
cd /etc/todo-api
pwd
ls -l
nano monitor.env
chown root:root monitor.env
chmod 0600 monitor.env
stat -c '%U %G %a %n' api.env monitor.env
exit
sudo /usr/local/sbin/todo-api-monitor --test
```

Visa att testnotisen når er Discord-kanal. Kör därefter en vanlig kontroll.

```bash
sudo /usr/local/sbin/todo-api-monitor
```

Cron-filen ligger i `/etc/cron.d/todo-api`. Där finns både backupjobbet och den återkommande övervakningen. Visa filen i editorn och förklara de fem tidsfälten samt fältet med användarnamn. Dessa systemgemensamma cron-filer har ett användarfält före kommandot. [Ubuntu om cron-formatet](https://manpages.ubuntu.com/manpages/noble/man5/crontab.5.html)

```bash
cd /etc/cron.d
sudo nano todo-api
sudo systemctl status cron --no-pager
timedatectl
sudo tail -n 20 /var/log/todo-api-backup.log
sudo tail -n 20 /var/log/todo-api-monitor.log
```

Backupen är schemalagd till `02:00` varje dygn med `0 2 * * *`. Övervakningen körs var femte minut med `*/5 * * * *`. Läs klockslag enligt serverns tidszon som visas av `timedatectl`. Installationsskriptet har skapat loggfilerna, som kan vara tomma fram till första schemalagda körningen. Vänta under repetitionen tills ett schemalagt jobb verkligen har körts och kontrollera dess logg. Ett manuellt test visar att skriptet fungerar. Den schemalagda körningen visar också att cron-konfigurationen fungerar.

**12. Felsök från utsidan och inåt**

| Vad ni ser | Nästa kontroll |
|---|---|
| SSH får timeout | Instansstatus, Elastic IP och port 22 från datorns aktuella publika IP. |
| SSH nekas med publickey | Användarnamnet `ubuntu`, rätt privat nyckel och motsvarande rad i `authorized_keys`. |
| Webbläsaren får timeout | Port 80 i security group och att Nginx är igång. |
| Nginx svarar 502 | `systemctl status todo-api`, tjänstens logg och anrop direkt till `127.0.0.1:8000/health`. |
| `/health` fungerar men `/ready` ger 503 | PostgreSQLs status, databasroll, inställningar och att tabellen har skapats. |
| Ingen Discord-notis kommer | Testkommandots resultat, rättigheter till `monitor.env`, webhook-inställningen och övervakningens logg. |

Titta också på `sudo nginx -t`, `sudo ss -lntp` och `sudo systemctl status postgresql --no-pager`. Förklara vad nästa kontroll kan skilja åt innan ni ändrar något.

**13. Fördela videon och håll tidsmarginal**

Det här är ett förslag på 54 minuter. Justera efter er repetition och behåll marginal till gränsen på 60 minuter.

| Tid | Moment | Förslag på ansvar |
|---|---|---|
| 0–3 min | Team, arkitektur och vad som ska demonstreras. | Båda förklarar varsin del. |
| 3–13 min | Ny EC2, nytt nyckelpar, security group och Elastic IP. | A arbetar, B förklarar nätverk och val. |
| 13–19 min | SSH från båda datorerna och SCP av skript. | B visar sin anslutning och förklarar nycklarna. |
| 19–31 min | Grundinstallation, Git-kloning, Python-miljö och PostgreSQL. | B arbetar, A förklarar användare och rättigheter. |
| 31–40 min | Systemd och Nginx med filgranskning i nano. | A arbetar, B förklarar trafikflödet. |
| 40–46 min | Publik `/docs`, CRUD, omstart och sparad data. | B visar flödet, A förklarar databasen. |
| 46–52 min | Backup, cron och testad Discord-notis. | A och B visar varsin del. |
| 52–54 min | Kontrollera bevis och förklara avstängningen. | Båda knyter sina tekniska val till kraven. |

Båda ska synas i kamera, höras och använda varsin dator. Ha läsbar terminaltext och arbeta med en checklista. Förklara kommandon, mappar, rättigheter och tekniska val med egna ord. Övningen ska ge er underlag att förklara det ni genomför.

**14. Kontrollera inspelningen och stäng av instansen**

Kontrollera att video och ljud fungerar, att båda syns och hörs och att terminaltexten går att läsa. Kontrollera videolänken med den åtkomst som läraren ska använda. Stoppa sedan rätt instans från EC2-konsolen och kontrollera att dess tillstånd blir `Stopped`. En stoppad instans finns kvar och kan startas igen. [AWS om att stoppa och starta EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Stop_Start.html)

Kontrollera även kvarvarande lagring och Elastic IP i AWS faktureringsöversikt. Stoppa instansen och hantera resursernas fortsatta kostnader som separata moment. När ni är helt klara med resurserna kan ni planera borttagning och släppa adressen. Spara först de data ni behöver. [AWS om Elastic IP och debitering](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html)

G-genomgången är redo när båda kan utföra och förklara momenten, ni har verifierat dem på servern och ni klarar hela flödet från en ny instans inom videons tidsgräns.
