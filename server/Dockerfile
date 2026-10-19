FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY optcg_sync.py .

# run as nobody-in-particular; the database lives on the /data volume
RUN useradd --system --uid 10001 optcg && mkdir /data && chown optcg /data
USER optcg
ENV OPTCG_SYNC_DB=/data/optcg-sync.db

EXPOSE 8787
# only the reverse proxy can reach this port (it's never published to the host),
# so trust its X-Forwarded-For for the real client IP
CMD ["uvicorn", "optcg_sync:app", "--host", "0.0.0.0", "--port", "8787", \
     "--proxy-headers", "--forwarded-allow-ips", "*", "--no-server-header"]
