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
char*      asctime_r  (const struct tm*, char*);
time_t     mktime     (struct tm*);
]]

local TimeStructP = ffi.typeof("struct tm[1]")
local TimeStruct = ffi.typeof("struct tm")
local TimeP = ffi.typeof("time_t[1]")
local Buf = ffi.typeof("uint8_t[?]")

local function gmtime(sec)
    local c = ffi.C.gmtime_r(TimeP(sec), TimeStruct())
    return {
        year  = c.year+1900, 
        month = c.month+1, 
        day   = c.day, 
        hour  = c.hour,
        min   = c.min,
        sec   = c.sec}
end
local function localtime(sec)
    local c = ffi.C.localtime_r(TimeP(sec), TimeStruct())
    return {
        year  = c.year+1900, 
        month = c.month+1, 
        day   = c.day, 
        hour  = c.hour,
        min   = c.min,
        sec   = c.sec}
end
local function mktime(t)
    local r = ffi.C.mktime(TimeStruct(
        t.sec or 0, 
        t.min or 0, 
        t.hour or 0,
        t.day, 
        t.month - 1, 
        t.year - 1900))
    -- r is cdata, need to convert to lua number
    return tonumber(r)
end
local function asctime(t)
    local buf = Buf(26)
    ffi.C.asctime_r(TimeStruct(
        t.sec or 0, 
        t.min or 0, 
        t.hour or 0,
        t.day, 
        t.month - 1, 
        t.year - 1900), buf)
    return ffi.string(buf)
end
local function strfmt(t)
  return string.format('%04d-%02d-%02d %02d:%02d:%02d', 
      t.year,  t.month,  t.day, 
      t.hour or 0,  t.min or 0,  t.sec or 0)
end

local datetimematch
if ngx~=nil then
    function datetimematch(value)
        return ngx.re.match(value,[[^(\d\d\d\d)-(\d\d?)-(\d\d?) (\d\d?):(\d\d?):(\d\d?)$]],'jo')
    end
else
    function datetimematch(value)
        return {value:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?) (%d%d?):(%d%d?):(%d%d?)$")}
    end
end

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
            t.number = mktime(t.table)
            return t.number
        elseif rawget(t,'table') then
            t.number= mktime(t.table)
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
function  datetime.new(arg)        
    return setmetatable({[type(arg)]=arg}, datetime)
end


local function test(...)
    local a = datetime.new(os.time())
    local b = datetime.new(os.date('*t')) 
    local c = a + timedelta.new{day=3}
    local d = b - timedelta.new{day=4}
    print('3 days after  '..tostring(a)..' is '..tostring(c))
    print('4 days before '..tostring(b)..' is '..tostring(d))

    local n= 0
    local s= '1970-01-01 00:00:00'
    local t= {year=1970,month=1,day=1}
    for i,v in ipairs({n,s,t}) do
       local r = datetime.new(v)
       print(r, r.number)
    end
    print(datetime.new('1969-1-01 0:02:00')>datetime.new(s))
    print(datetime.new('1970-1-1 3:2:0')>datetime.new(s))
end
--test()
return {
    datetime=datetime,
    timedelta=timedelta,
    gmtime=gmtime,
    localtime=localtime,
    mktime=mktime,
}


