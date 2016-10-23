local gmtime, localtime, mktime, datetimematch

if ngx then
    function datetimematch(value)
        return ngx.re.match(value,[[^(\d\d\d\d)-(\d\d?)-(\d\d?) (\d\d?):(\d\d?):(\d\d?)$]],'jo')
    end
else
    function datetimematch(value)
        return {value:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?) (%d%d?):(%d%d?):(%d%d?)$")}
    end
end

local is_windows = package.config:sub(1,1) == '\\'
if is_windows then
    function gmtime(sec)
        return os.date('!*t', sec)
    end
    function localtime(sec)
        return os.date('*t', sec)
    end
    function mktime(t)
        return os.time(t)
    end
else
    local ffi = require("ffi")
    ffi.cdef[[
typedef long  time_t;
typedef struct tm {
  int sec;        /* secs. [0-60] (1 leap sec) */
  int min;        /* mins. [0-59] */
  int hour;          /* Hours.   [0-23] */
  int day;           /* Day.     [1-31] */
  int month;         /* Month.   [0-11] */
  int year;          /* Year - 1900.  */
  int wday;          /* Day of week. [0-6] */
  int yday;          /* Days in year.[0-365] */
  int isdst;         /* DST.     [-1/0/1]*/
  long int gmtoff;   /* secs east of UTC.  */
  const char* zone;  /* Timezone abbreviation.  */
} tm;
struct tm* gmtime_r   (const time_t*, struct tm*);
struct tm* localtime_r(const time_t*, struct tm*);
time_t     mktime     (struct tm*);
]]
    local TimeStructP = ffi.typeof("struct tm[1]")
    local TimeStruct = ffi.typeof("struct tm")
    local TimeP = ffi.typeof("time_t[1]")
    local Buf = ffi.typeof("uint8_t[?]")
    function gmtime(sec)
        local c = ffi.C.gmtime_r(TimeP(sec), TimeStruct())
        return {
            year  = c.year+1900, 
            month = c.month+1, 
            day   = c.day, 
            hour  = c.hour,
            min   = c.min,
            sec   = c.sec}
    end
    function localtime(sec)
        local c = ffi.C.localtime_r(TimeP(sec), TimeStruct())
        return {
            year  = c.year+1900, 
            month = c.month+1, 
            day   = c.day, 
            hour  = c.hour,
            min   = c.min,
            sec   = c.sec}
    end
    function mktime(t)
        local r = ffi.C.mktime(TimeStruct(
            t.sec or 0, 
            t.min or 0, 
            t.hour or 0,
            t.day, 
            t.month - 1, 
            t.year - 1900))
        -- r is cdata, need to be converted to lua number
        return tonumber(r)
    end
end

local function strfmt(t)
  return string.format('%04d-%02d-%02d %02d:%02d:%02d', 
      t.year,  t.month,  t.day, 
      t.hour or 0,  t.min or 0,  t.sec or 0)
end
local function logt(t)
    print(t.year,  t.month,  t.day, t.hour,  t.min,  t.sec)
end

-- timedelta object
local delta_to_sec = {
  sec  = 1, 
  min  = 60, 
  hour = 60*60, 
  day  = 60*60*24, 
  week = 60*60*24*7, 
}
local timedelta = {is_timedelta=true}
timedelta.__index = timedelta
function  timedelta.new(attrs)        
    local self = {}
    local t = 0
    for k, v in pairs(attrs) do
        t = t + (delta_to_sec[k] or 0) * v
    end
    self.total_seconds = t
    return setmetatable(self, timedelta)
end
function  timedelta.weeks(self)        
    return (math.modf(self.total_seconds/604800))
end
function  timedelta.days(self)        
    return (math.modf(self.total_seconds/86400))
end
function  timedelta.hours(self)        
    return (math.modf(self.total_seconds/3600))
end
function  timedelta.mins(self)        
    return (math.modf(self.total_seconds/60))
end

-- datetime object
local  datetime = {}
local function index(t, k)
    if k=='string' then 
        if rawget(t,'table') then
            t.string = strfmt(t.table)
            return t.string
        elseif rawget(t,'number') then
            t.table = localtime(t.number)
            t.string = strfmt(t.table)
            return t.string
        end
    elseif k=='table' then
        if rawget(t,'string') then
            local m, e = datetimematch(t.string)
            if not m then
                return nil
            end
            t.table = { 
                year = tonumber(m[1]),
                month= tonumber(m[2]),
                day  = tonumber(m[3]),
                hour = tonumber(m[4]),
                min  = tonumber(m[5]),
                sec  = tonumber(m[6]),
            }
            return t.table
        elseif rawget(t,'number') then
            t.table = localtime(t.number)
            t.string = strfmt(t.table)
            return t.table
        end
    elseif k=='number' then
        if rawget(t,'string') then
            local m, e = datetimematch(t.string)
            if not m then
                return nil
            end
            t.table = { 
                year = tonumber(m[1]),
                month= tonumber(m[2]),
                day  = tonumber(m[3]),
                hour = tonumber(m[4]),
                min  = tonumber(m[5]),
                sec  = tonumber(m[6]),
            }
            t.number = mktime(t.table) or 0 -- in case of overflow
            return t.number
        elseif rawget(t,'table') then
            t.number= mktime(t.table) or 0 
            t.string = strfmt(t.table)
            return t.number
        end
    else
        return nil
    end
end
local function lt(a, b)
    return a.number < b.number
end
local function le(a, b)
    return a<b or a==b
end
local function eq(a, b)
    return a.number == b.number
end
local function sub(a, b)
    -- two datetime or one datetime and one timedelta
    if b.is_timedelta then
        return datetime.new(a.number - b.total_seconds)
    else
        return timedelta.new{sec = a.number - b.number}
    end
end
local function add(a, b)
    -- one datetime and one timedelta
    return datetime.new(a.number + b.total_seconds)
end
datetime.__index=index
datetime.__lt=lt
datetime.__le=le
datetime.__eq=eq
datetime.__sub=sub 
datetime.__add=add
datetime.__tostring=function(t) return t.string end

function datetime.new(arg)    
    return setmetatable({[type(arg)]=arg}, datetime)
end


local function test()
    local now_table = os.date('*t')
    local now_number = os.time(now_table)
    local now_string = strfmt(now_table)
    print('current localtime is', now_string, 'correspondent timestamp is', now_number)
    -- create a datetime object in three ways:
    local dtt = datetime.new(now_table) 
    local dtn = datetime.new(now_number)
    local dts = datetime.new(now_string)
    assert(dtt==dtn and dtn==dts, 'these three datetime object should be equal')
    local diff_days = 2
    local diff_hours = 1
    -- seconds = 2*24*3600 + 3600 = 176400
    local diff = timedelta.new{day=diff_days, hour=diff_hours}
    print(string.format('%s days and %s hour after   %s is %s(by table)', diff_days, diff_hours, dtt, dtt+diff))
    print(string.format('%s days and %s hour after   %s is %s(by number)', diff_days, diff_hours, dtn, dtn+diff))
    print(string.format('%s days and %s hour after   %s is %s(by string)', diff_days, diff_hours, dts, dts+diff))
    print(string.format('%s days and %s hour before  %s is %s(by table)', diff_days, diff_hours, dtt, dtt-diff))
    print(string.format('%s days and %s hour before  %s is %s(by number)', diff_days, diff_hours, dtn, dtn-diff))
    print(string.format('%s days and %s hour before  %s is %s(by string)', diff_days, diff_hours, dts, dts-diff))
    local dto = dtt + timedelta.new{hour=1, sec=1}
    print(string.format('%s is later   than %s by %s seconds', dto, dtt, (dto - dtt).total_seconds))
    local dto = dtt - timedelta.new{hour=1, sec=2}
    print(string.format('%s is earlier than %s by %s seconds', dto, dtt, (dtt - dto).total_seconds))
end

return {
    datetime=datetime,
    timedelta=timedelta,
    gmtime=gmtime,
    localtime=localtime,
    mktime=mktime,
    test=test,
}


