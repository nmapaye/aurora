"""Independent RK4 numerical reference; does not import the TypeScript code.

Implements the differential dynamics behind Ingre et al. (2014) eqs 1.1–1.9.
Research verification only: generated values are NOT observed human KSS data.
"""
import json, math
from datetime import datetime, timezone, timedelta
from pathlib import Path
H=14.3; L=2.4; G=math.log((H-14)/(H-7.96))/8
base=datetime(2026,10,20,23,tzinfo=timezone.utc)

def integrate(s, duration, asleep):
    # Adaptive final step, otherwise 3.6-second RK4 steps; independent of the
    # TypeScript closed-form wake and piecewise sleep implementation.
    def f(x):
        return -G*(H-max(x,12.2)) if asleep else -.0353*(x-L)
    left=duration
    while left > 1e-10:
        dt=min(.001,left)
        k1=f(s);k2=f(s+dt*k1/2);k3=f(s+dt*k2/2);k4=f(s+dt*k3)
        s+=dt*(k1+2*k2+2*k3+k4)/6
        left-=dt
    return s

def terms(t, phase):
    tod=t.hour+t.minute/60+t.second/3600
    return 2.5*math.cos(2*math.pi/24*(tod-phase)), -.5+.5*math.cos(2*math.pi/12*(tod-phase-3))

rows=[]
for duration in [4,6,8,10]:
 for awake in [0,4,12,16]:
    timeline=[]; t=base
    for state,hours in [('sleep',8),('awake',16),('sleep',duration),('awake',awake)]:
        if hours:
            end=t+timedelta(hours=hours)
            timeline.append({'state':state,'start':t.timestamp()*1000,'end':end.timestamp()*1000})
            t=end
    c,u=terms(base,16.8);s=8.38-c-u
    for seg in timeline: s=integrate(s,(seg['end']-seg['start'])/3600000,seg['state']=='sleep')
    c,u=terms(t,16.8);w=-5.72*math.exp(-1.51*awake)
    raw=10.6-.6*(s+c+u+w)
    rows.append({'name':f'{duration}h sleep then {awake}h awake','input':{'at':t.timestamp()*1000,'timeZone':'UTC','phaseHours':16.8,'history':timeline,'caffeine':{'complete':True,'doses':[]}},'expected':{'homeostatic':s,'circadian':c,'ultradian':u,'inertia':w,'rawKss':raw}})
Path(__file__).with_name('fixtures').joinpath('tpm-reference.json').write_text(json.dumps({'kind':'Independent numerical reference, not clinical observations','source':'Ingre et al. 2014, DOI 10.1371/journal.pone.0108679, eqs 1.1–1.9','method':'Python RK4, maximum step 0.001 hours; TS uses analytic propagation','cases':rows},indent=2)+'\n')
print('Wrote',len(rows),'independent numerical fixtures.')
