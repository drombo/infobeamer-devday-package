from __future__ import print_function

import calendar
import traceback
import urllib
from datetime import timedelta
from operator import itemgetter

import pytz

import dateutil.parser
import defusedxml.ElementTree as ET


def get_schedule(url):
    def load_events(xml):
        def to_unixtimestamp(dt):
            dt = dt.astimezone(pytz.utc)
            ts = int(calendar.timegm(dt.timetuple()))
            return ts

        def text_or_empty(node, child_name):
            child = node.find(child_name)
            if child is None:
                return u""
            if child.text is None:
                return u""
            return unicode(child.text)

        def parse_duration(value):
            h, m = map(int, value.split(':'))
            return timedelta(hours=h, minutes=m)

        def all_events():
            schedule = ET.fromstring(xml)
            for day in schedule.findall('day'):
                for room in day.findall('room'):
                    for event in room.findall('event'):
                        yield event

        parsed_events = []
        for event in all_events():
            start = dateutil.parser.parse(event.find('date').text)
            duration = parse_duration(event.find('duration').text)
            end = start + duration

            persons = event.find('persons')
            if persons is not None:
                persons = persons.findall('person')

            parsed_events.append(dict(
                start=start.astimezone(pytz.utc),
                start_str=start.strftime('%H:%M'),
                end_str=end.strftime('%H:%M'),
                start_unix=to_unixtimestamp(start),
                end_unix=to_unixtimestamp(end),
                duration=int(duration.total_seconds() / 60),
                title=text_or_empty(event, 'title'),
                abstract=text_or_empty(event, 'abstract'),
                place=text_or_empty(event, 'room'),
                speakers=[
                    unicode(person.text.strip())
                    for person in persons
                    ] if persons else [],
                lang=text_or_empty(event, 'language') or "unk",
                id=event.attrib["id"],
                type="talk",
            ))
        parsed_events.sort(key=itemgetter('start_unix'))
        return parsed_events

    try:
        resp = urllib.urlopen(url)
        schedule = resp.read()
        events = load_events(schedule)
    except Exception as err:
        traceback.print_exc()
        return False, None

    return True, events


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description="Importer for Infobeamer XML")
    parser.add_argument(dest="url")
    arguments = parser.parse_args()

    print(get_schedule(arguments.url))
