box.cfg{
	listen = 3301,
	log_level = 5,
	-- logger = 'tarantool.log'
}

s = box.space.tester
s2 = box.space.sophier
if s then
	s:drop{}
else
	box.schema.user.grant('guest','read,write,execute','universe')
end

if s2 then
	s:drop{}
end


s = box.schema.space.create('tester', {id = 1})
_format = {}
_format[1] = {type='str', name='_t1'}
_format[2] = {type='str', name='_t2'}
_format[3] = {type='num', name='_t3'}
_format[4] = {type='num', name='_t4'}
s:format(_format)

i = s:create_index('primary', {type = 'tree', parts = {1, 'STR', 2, 'STR', 3, 'NUM'}})


arr = {1, 2, 3, "str1", 4}
obj = {}
obj['key1'] = "value1"
obj['key2'] = 42
obj[33] = true
obj[35] = false

-- box.space[1]:insert{"t1", "t2", 1, -745, "heyo"};
-- box.space[1]:insert{"t1", "t2", 2, arr};
-- box.space[1]:insert{"t1", "t2", 3, obj};
-- box.space[1]:insert{"tt1", "tt2", 456};

function string_function()
  return "hello world"
end



s2 = box.schema.space.create('sophier', {engine = 'sophia'})
i2 = s2:create_index('primary', {type = 'tree', parts = {1, 'STR'}})
