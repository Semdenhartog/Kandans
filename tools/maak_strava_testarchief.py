"""Maakt test/fixtures/strava_export*.zip: een klein nep-archief zoals Strava het levert.

python3 tools/maak_strava_testarchief.py
"""
import gzip
import io
import math
import struct
import zipfile
from datetime import datetime, timedelta, timezone

FIT_EPOCH = datetime(1989, 12, 31, tzinfo=timezone.utc)
START = datetime(2024, 5, 4, 7, 30, tzinfo=timezone.utc)


def semi(deg):
    return int(round(deg * (2 ** 31) / 180))


def fit_file(sport=1, n=120):
    """Een FIT met 60 gewone en daarna compacte tijdstempels, plus een sessie met de sport."""
    body = bytearray()
    # Definitie 0: record met tijd.
    body += bytes([0x40, 0, 0]) + struct.pack('<H', 20) + bytes([6])
    body += bytes([253, 4, 0x86, 0, 4, 0x85, 1, 4, 0x85, 78, 4, 0x86, 3, 1, 0x02, 5, 4, 0x86])
    # Definitie 1: record zonder tijd (voor compacte koppen), met een ontwikkelaarsveld (wordt overgeslagen).
    body += bytes([0x40 | 0x20 | 1, 0, 0]) + struct.pack('<H', 20) + bytes([5])
    body += bytes([0, 4, 0x85, 1, 4, 0x85, 78, 4, 0x86, 3, 1, 0x02, 5, 4, 0x86])
    body += bytes([1, 0, 2, 0])  # 1 ontwikkelaarsveld van 2 bytes
    t0 = int((START - FIT_EPOCH).total_seconds())
    lat0, lon0 = 52.15, 5.60
    for i in range(n):
        ts = t0 + i
        lat = lat0 + i * 3 / 111_320  # 3 m per seconde naar het noorden
        alt = int(round((20 + i * 0.05 + 500) * 5))
        hr = 120 + i // 4
        dist = i * 300  # cm
        if i < 60:
            body += bytes([0x00]) + struct.pack('<IiiIBI', ts, semi(lat), semi(lon0), alt, hr, dist)
        else:
            body += bytes([0x80 | (1 << 5) | (ts & 0x1F)]) + struct.pack('<iiIBI', semi(lat), semi(lon0), alt, hr, dist) + b'\xAB\xCD'
    # Definitie 2: session met sport.
    body += bytes([0x42, 0, 0]) + struct.pack('<H', 18) + bytes([2]) + bytes([253, 4, 0x86, 5, 1, 0x00])
    body += bytes([0x02]) + struct.pack('<IB', t0 + n, sport)
    header = bytes([14, 0x20]) + struct.pack('<HI', 2132, len(body)) + b'.FIT' + b'\x00\x00'
    return header + bytes(body) + b'\x00\x00'


def gpx_file(start, n=100):
    pts = []
    for i in range(n):
        t = (start + timedelta(seconds=i * 2)).strftime('%Y-%m-%dT%H:%M:%SZ')
        pts.append(f'<trkpt lat="{52.2 + i * 6 / 111_320:.7f}" lon="5.65"><ele>{10 + i * 0.1:.1f}</ele><time>{t}</time></trkpt>')
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<gpx creator="StravaGPX" version="1.1" xmlns="http://www.topografix.com/GPX/1/1">'
            f'<metadata><time>{start.isoformat()}</time></metadata><trk><name>Avondloop</name><type>running</type><trkseg>'
            + ''.join(pts) + '</trkseg></trk></gpx>')


def tcx_file(start, n=100):
    pts = []
    for i in range(n):
        t = (start + timedelta(seconds=i * 2)).strftime('%Y-%m-%dT%H:%M:%SZ')
        pts.append(f'<Trackpoint><Time>{t}</Time><Position><LatitudeDegrees>{52.3 + i * 5 / 111_320:.7f}</LatitudeDegrees>'
                   f'<LongitudeDegrees>5.7</LongitudeDegrees></Position><DistanceMeters>{i * 5}</DistanceMeters>'
                   f'<HeartRateBpm><Value>{130 + i % 10}</Value></HeartRateBpm></Trackpoint>')
    # Strava/Garmin-TCX begint soms met spaties vóór de XML-kop.
    return ('          <?xml version="1.0" encoding="UTF-8"?>\n<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">'
            '<Activities><Activity Sport="Running"><Lap><Track>' + ''.join(pts) + '</Track></Lap></Activity></Activities></TrainingCenterDatabase>')


CSV = (
    'Activity ID,Activity Date,Activity Name,Activity Type,Activity Description,Elapsed Time,Distance,Filename\n'
    '111,"May 4, 2024, 7:30:00 AM",Ochtendloop,Run,"Lekker, met\nregeleinde en ""quotes""",120,0.36,activities/111.fit.gz\n'
    '222,"May 5, 2024, 7:30:00 PM",Avondloop,Run,,200,0.6,activities/222.gpx\n'
    '333,"May 6, 2024, 6:00:00 PM",Trail,Trail Run,,200,0.5,activities/333.tcx.gz\n'
    '444,"May 7, 2024, 6:00:00 PM",Fietsen,Ride,,600,5.0,activities/444.gpx\n'
    '555,"May 8, 2024, 6:00:00 PM",Loopband,Run,,600,2.0,\n'
)


def build(path, force_zip64=False):
    # Met limiet 0 schrijft Python overal zip64-velden (ook in de inhoudsopgave en het eindblok).
    zipfile.ZIP64_LIMIT = 0 if force_zip64 else (1 << 31) - 1
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        def put(name, data):
            with z.open(name, 'w', force_zip64=force_zip64) as f:
                f.write(data)
        put('profile.csv', b'Athlete ID\n1\n')
        put('activities.csv', CSV.encode())
        put('activities/111.fit.gz', gzip.compress(fit_file()))
        put('activities/222.gpx', gpx_file(START + timedelta(days=1, hours=12)).encode())
        put('activities/333.tcx.gz', gzip.compress(tcx_file(START + timedelta(days=2, hours=10, minutes=30)).encode()))
        put('activities/444.gpx', gpx_file(START + timedelta(days=3)).encode())
    data = bytearray(buf.getvalue())
    if force_zip64:
        # Eindblok op "zie zip64" zetten, zoals bij echt grote archieven.
        i = data.rfind(b'PK\x05\x06')
        data[i + 8:i + 20] = b'\xff' * 12
    with open(path, 'wb') as f:
        f.write(bytes(data))


if __name__ == '__main__':
    build('test/fixtures/strava_export.zip')
    build('test/fixtures/strava_export_zip64.zip', force_zip64=True)
    with open('test/fixtures/fietsrit.fit', 'wb') as f:
        f.write(fit_file(sport=2, n=30))
    print('klaar')
