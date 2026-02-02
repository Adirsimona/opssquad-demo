FROM python:3.11-slim

RUN apt-get update && apt-get install -y curl bash procps && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3004

ENTRYPOINT ["/entrypoint.sh"]
