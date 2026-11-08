Todo-API med FastAPI och PostgreSQL. Varje uppgift har ett automatiskt genererat `id`, en obligatorisk `title` och `completed`, som börjar med värdet `false`.

Databasens tabell och kolumner visas i projektets [ER-diagram](docs/ERD.md).

**Installera och starta lokalt på Windows**

1. Installera PostgreSQL och skapa databasen `todo_db`, exempelvis i pgAdmin. Databasservern behöver vara igång. Den lokala konfigurationen använder användaren `postgres`. Använd en separat applikationsroll vid serverinstallationen.

2. Öppna PowerShell i projektmappen. Skapa och aktivera en virtuell miljö, och installera beroendena.

   ```powershell
   python -m venv venv
   .\venv\Scripts\Activate.ps1
   python -m pip install -r requirements.txt
   ```

   Aktivera miljön när du öppnar en ny terminal. Om du redan har en miljö kan du använda den.

3. Skapa `.env` i projektmappen med hjälp av `env.example`. Ange rätt databasnamn och ditt lokala databaslösenord.

   ```dotenv
   DATABASE_NAME=todo_db
   PASSWORD="your_database_password"
   DATABASE_USER=postgres
   DATABASE_HOST=localhost
   DATABASE_PORT=5432
   ```

   Systemets miljövariabler har företräde framför `.env`. `.env` är undantagen från Git.

4. Skapa tabellen. Kommandot kan köras igen när tabellen redan finns. Senare ändringar av tabellens struktur behöver genomföras separat.

   ```powershell
   python db_setup.py
   ```

5. Starta API:t för lokal utveckling.

   ```powershell
   python -m uvicorn app:app --reload
   ```

   Öppna [Swagger](http://127.0.0.1:8000/docs) för att prova anropen. `--reload` startar om utvecklingsservern när Python-filer sparas. Systemd får ett separat startkommando vid serverinstallationen.

**Anrop**

| Metod | Adress | Funktion | Lyckat svar |
|---|---|---|---|
| GET | `/Todo/list` | Lista uppgifter i id-ordning. | 200 med `items`. |
| POST | `/Todo` | Skapa en uppgift med `title`. | 201 med uppgiften. |
| GET | `/Todo/{todo_id}` | Hämta en uppgift. | 200 med uppgiften. |
| PATCH | `/Todo/{todo_id}` | Ändra `title`, `completed` eller båda. | 200 med uppgiften. |
| DELETE | `/Todo/{todo_id}` | Radera en uppgift. | 204 med tom svarskropp. |
| GET | `/health` | Kontrollera att API:t svarar. | 200. |
| GET | `/ready` | Kontrollera anslutningen och åtkomsten till todo-tabellen. | 200, eller 503 vid databasfel. |

Saknade uppgifter ger 404. Id:n med fel datatyp och ogiltig indata ger 422. Titel trimmas och måste innehålla text. PATCH kräver minst ett ändringsfält och avvisar uttryckliga `null`-värden. För utelämnade fält använder SQL-frågan det befintliga databasvärdet.

**Kontrollera ett helt flöde**

1. Skapa en testuppgift med POST och spara dess id.
2. Läs den med GET och kontrollera listan.
3. Uppdatera bara titeln, därefter `completed` till `true` och tillbaka till `false`.
4. Starta om API:t och läs samma uppgift igen.
5. Radera testuppgiften. GET och en upprepad DELETE ska därefter ge 404.
6. Prova tom titel, tom PATCH, `null` och bokstäver i id-fältet. Dessa ska ge 422.

**Filernas ansvar**

- `app.py` tar emot HTTP-anrop, hanterar statuskoder och stänger anslutningar.
- `schemas.py` validerar inkommande data med Pydantic.
- `db.py` utför parametriserade SQL-frågor och returnerar resultat.
- `db_setup.py` läser konfiguration, öppnar databasanslutningar och initierar tabellen.

**Serverfiler för G-delen**

Installationsskript finns i `scripts/` och serverkonfigurationer i `deploy/`. Följ [G-guiden](deploy/G-guide.md) för körordning, överföring, PostgreSQL, systemd, Nginx, backup, cron och Discord-notifieringar. Serverfilerna använder Ubuntu Server 24.04 LTS eller senare, en lokal PostgreSQL-server och applikationskontot `api`.

För över `scripts/setup-server.sh` med SCP och kör det med `sudo bash` på servern. Därefter klonas branchen `Tadios` till `/home/api/todo-api`, den virtuella miljön installeras och databas- samt konfigurationsskripten körs enligt guiden. Den färdiga koden behöver finnas i det Git-repo som servern klonar.

EC2-instans, Elastic IP, security groups, bådas SSH-åtkomst, faktisk serverinstallation, schemalagda körningar, Discord-leverans och videogenomgång verifieras på er server under förberedelserna och examinationen.
