os = require('os')
env = require('test_run')
math = require('math')
fiber = require('fiber')
test_run = env.new()

NUM_INSTANCES = 5
SERVERS = {}
for i=1,NUM_INSTANCES do                                                       \
    SERVERS[i] = 'qsync' .. i                                                  \
end;
SERVERS -- print instance names

math.randomseed(os.time())
random = function(excluded_num, min, max)                                      \
    local r = math.random(min, max)                                            \
    if (r == excluded_num) then                                                \
        return random(excluded_num, min, max)                                  \
    end                                                                        \
    return r                                                                   \
end

-- Pick a random replica in a cluster.
-- Promote it to a leader.
-- Pick a random replica and make sure inserted "1" is there.
-- Switch to a leader, delete "1",
--   set "broken quorum" on it and insert "1" again.

-- Testcase setup.
test_run:create_cluster(SERVERS)
test_run:wait_fullmesh(SERVERS)
test_run:switch('qsync1')
_ = box.schema.space.create('sync', {engine = test_run:get_cfg('engine')})
_ = box.space.sync:create_index('primary')
test_run:switch('default')
current_leader_id = 1
test_run:eval(SERVERS[current_leader_id], "box.ctl.clear_synchro_queue()")

-- Testcase body.
for i=1,100 do                                                                 \
    test_run:eval(SERVERS[current_leader_id],                                  \
        "box.cfg{replication_synchro_quorum=6}")                               \
    test_run:eval(SERVERS[current_leader_id],                                  \
        string.format("box.space.sync:insert{%d}", i))                         \
    new_leader_id = random(current_leader_id, 1, #SERVERS)                     \
    test_run:eval(SERVERS[new_leader_id],                                      \
        "box.cfg{replication_synchro_quorum=3}")                               \
    test_run:eval(SERVERS[new_leader_id], "box.ctl.clear_synchro_queue()")     \
    replica = random(new_leader_id, 1, #SERVERS)                               \
    test_run:eval(SERVERS[replica],                                            \
        string.format("box.space.sync:get{%d}", i))                            \
    test_run:switch('default')                                                 \
    current_leader_id = new_leader_id                                          \
end

test_run:switch('qsync1')
box.space.sync:count() -- 100

-- Teardown.
test_run:switch('default')
test_run:eval(SERVERS[current_leader_id], 'box.space.sync:drop()')
test_run:drop_cluster(SERVERS)
