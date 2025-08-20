"""
Alert-System für die Heizungsüberwachung
Sendet Benachrichtigungen bei kritischen Ereignissen
"""

import logging
import smtplib
import requests
import json
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import os

logger = logging.getLogger(__name__)

class AlertManager:
    """Verwaltet Alarme und Benachrichtigungen"""
    
    def __init__(self):
        self.last_alerts = {}  # Verhindert Spam
        self.alert_cooldown = timedelta(minutes=30)  # 30 Min zwischen gleichen Alarmen
        
        # E-Mail Konfiguration
        self.email_enabled = os.getenv('ALERT_EMAIL_ENABLED', 'false').lower() == 'true'
        self.smtp_server = os.getenv('SMTP_SERVER', 'smtp.gmail.com')
        self.smtp_port = int(os.getenv('SMTP_PORT', 587))
        self.smtp_user = os.getenv('SMTP_USER', '')
        self.smtp_password = os.getenv('SMTP_PASSWORD', '')
        self.alert_email = os.getenv('ALERT_EMAIL', '')
        
        # Telegram Konfiguration
        self.telegram_enabled = os.getenv('TELEGRAM_ENABLED', 'false').lower() == 'true'
        self.telegram_token = os.getenv('TELEGRAM_BOT_TOKEN', '')
        self.telegram_chat_id = os.getenv('TELEGRAM_CHAT_ID', '')
        
        # Discord Webhook
        self.discord_enabled = os.getenv('DISCORD_ENABLED', 'false').lower() == 'true'
        self.discord_webhook = os.getenv('DISCORD_WEBHOOK_URL', '')
    
    def should_send_alert(self, alert_key: str) -> bool:
        """Prüft ob ein Alarm gesendet werden soll (Cooldown-Logik)"""
        now = datetime.now()
        
        if alert_key in self.last_alerts:
            last_sent = self.last_alerts[alert_key]
            if now - last_sent < self.alert_cooldown:
                return False
        
        self.last_alerts[alert_key] = now
        return True
    
    def send_email_alert(self, subject: str, message: str) -> bool:
        """Sendet E-Mail-Alarm"""
        if not self.email_enabled or not self.alert_email:
            return False
        
        try:
            msg = MIMEMultipart()
            msg['From'] = self.smtp_user
            msg['To'] = self.alert_email
            msg['Subject'] = f"🔥 Heizungsalarm: {subject}"
            
            body = f"""
Heizungsüberwachung - Alarm

Zeit: {datetime.now().strftime('%d.%m.%Y %H:%M:%S')}
Ereignis: {subject}

Details:
{message}

--
Automatische Benachrichtigung der Heizungsüberwachung
"""
            
            msg.attach(MIMEText(body, 'plain', 'utf-8'))
            
            with smtplib.SMTP(self.smtp_server, self.smtp_port) as server:
                server.starttls()
                server.login(self.smtp_user, self.smtp_password)
                server.send_message(msg)
            
            logger.info(f"✅ E-Mail-Alarm gesendet: {subject}")
            return True
            
        except Exception as e:
            logger.error(f"❌ E-Mail-Alarm fehlgeschlagen: {e}")
            return False
    
    def send_telegram_alert(self, message: str) -> bool:
        """Sendet Telegram-Alarm"""
        if not self.telegram_enabled or not self.telegram_token:
            return False
        
        try:
            text = f"🔥 *Heizungsalarm*\n\n{message}\n\n⏰ {datetime.now().strftime('%d.%m.%Y %H:%M:%S')}"
            
            url = f"https://api.telegram.org/bot{self.telegram_token}/sendMessage"
            data = {
                'chat_id': self.telegram_chat_id,
                'text': text,
                'parse_mode': 'Markdown'
            }
            
            response = requests.post(url, data=data, timeout=10)
            response.raise_for_status()
            
            logger.info(f"✅ Telegram-Alarm gesendet")
            return True
            
        except Exception as e:
            logger.error(f"❌ Telegram-Alarm fehlgeschlagen: {e}")
            return False
    
    def send_discord_alert(self, message: str) -> bool:
        """Sendet Discord-Alarm"""
        if not self.discord_enabled or not self.discord_webhook:
            return False
        
        try:
            data = {
                "embeds": [{
                    "title": "🔥 Heizungsalarm",
                    "description": message,
                    "color": 0xff0000,  # Rot
                    "timestamp": datetime.utcnow().isoformat(),
                    "footer": {
                        "text": "Heizungsüberwachung"
                    }
                }]
            }
            
            response = requests.post(
                self.discord_webhook, 
                json=data,
                headers={'Content-Type': 'application/json'},
                timeout=10
            )
            response.raise_for_status()
            
            logger.info(f"✅ Discord-Alarm gesendet")
            return True
            
        except Exception as e:
            logger.error(f"❌ Discord-Alarm fehlgeschlagen: {e}")
            return False
    
    def send_alert(self, alert_type: str, circuit: str, message: str):
        """Sendet einen Alarm über alle konfigurierten Kanäle"""
        alert_key = f"{alert_type}_{circuit}_{message}"
        
        if not self.should_send_alert(alert_key):
            logger.debug(f"Alarm-Cooldown aktiv für: {alert_key}")
            return
        
        subject = f"{alert_type.upper()} - {circuit}"
        full_message = f"Heizkreis: {circuit}\nTyp: {alert_type}\nMeldung: {message}"
        
        # Über alle Kanäle senden
        sent_count = 0
        
        if self.send_email_alert(subject, full_message):
            sent_count += 1
        
        if self.send_telegram_alert(full_message):
            sent_count += 1
        
        if self.send_discord_alert(full_message):
            sent_count += 1
        
        if sent_count > 0:
            logger.info(f"📢 Alarm über {sent_count} Kanal(e) gesendet: {subject}")
        else:
            logger.warning(f"⚠️ Kein Alarm-Kanal verfügbar für: {subject}")
    
    def process_system_alerts(self, alerts: List[Dict]):
        """Verarbeitet System-Alarme"""
        for alert in alerts:
            alert_type = alert.get('type', 'info')
            circuit = alert.get('circuit', 'system')
            message = alert.get('message', 'Unbekannter Alarm')
            
            # Nur kritische und Warnungen senden
            if alert_type in ['kritisch', 'critical', 'warnung', 'warning']:
                self.send_alert(alert_type, circuit, message)
    
    def test_notifications(self) -> Dict[str, bool]:
        """Testet alle Benachrichtigungskanäle"""
        test_message = "Test-Benachrichtigung der Heizungsüberwachung"
        
        results = {}
        
        if self.email_enabled:
            results['email'] = self.send_email_alert("Test", test_message)
        
        if self.telegram_enabled:
            results['telegram'] = self.send_telegram_alert(test_message)
        
        if self.discord_enabled:
            results['discord'] = self.send_discord_alert(test_message)
        
        return results
