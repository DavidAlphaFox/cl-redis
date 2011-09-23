;;; CL-REDIS testsuite package definition
;;; (c) Vsevolod Dyomkin, Oleksandr Manzyuk. see LICENSE file for permissions

(in-package :cl-user)

(defpackage #:redis-test
  (:use :common-lisp :rutils.user :rutils.short #+nuts :nuts
        :redis)
  (:export #:run-tests))

(in-package #:redis-test)

(deftest tell ()
  (with-connection ()
    (let ((*echo-p* t)
          (*echo-stream* (make-string-output-stream)))
      (check string=
             (progn (tell 'hget "h1" (format nil "~A~%~B" "f1" "~"))
                    (get-output-stream-string *echo-stream*))
             " > *3
 > $4
 > HGET
 > $2
 > h1
 > $4
 > f1
~
"))))

(defun expect-from-str (expected input)
  (sockets:with-open-socket (server :connect :passive
                                    :address-family :internet
                                    :type :stream
                                    :ipv6 nil
                                    :external-format '(:utf-8 :eol-style :crlf))
    (sockets:bind-address server sockets:+ipv4-unspecified+ :port 63799
                          :reuse-addr t)
    (sockets:listen-on server)
    (with-connection (:port 63799)
      (let* ((client (sockets:accept-connection server :wait t))
             (bt:*default-special-bindings*
              (append (list (cons '*connection* *connection*)
                            (cons '*trace-output* *trace-output*))
                      bt:*default-special-bindings*))
             (worker (bt:make-thread (lambda () (expect expected)))))
        (mapcar (lambda (x) (write-line x client))
                (mklist input))
        (finish-output client)
        (bt:join-thread worker)))))


(deftest expect ()
  (check true                  (expect-from-str :status "+OK"))
  (check string= "10$"         (expect-from-str :inline "+10$"))
  (check null                  (expect-from-str :boolean "+0$"))
  (check = 10                  (expect-from-str :integer "+10"))
  (check = 10.0                (expect-from-str :float '("+4" "10.0")))
  (check string= "abc"         (expect-from-str :bulk '("+3" "abc")))
  (check equal '("a" nil)      (expect-from-str :multi '("*2" "$1" "a" "$-1")))
  ;; undocumented case for $0, let's be on the safe side
  (check equal '("a" nil)      (expect-from-str :anything
                                                '("*2" "$1" "a" "$0" "")))
  (check equal '("a" "b" "c")  (expect-from-str :list '("+5" "a b c")))
  (check equal '("OK" ("a"))   (expect-from-str :queued
                                                '("*2" "+OK" "*1" "$1" "a")))
  (check equal '(("subscribe" "chan1" "1") ("subscribe" "chan2" "2"))
                               (expect-from-str :pubsub
                                                '("*3" "$9" "subscribe"
                                                  "$5" "chan1" ":1"
                                                  "*3" "$9" "subscribe"
                                                  "$5" "chan2" ":2"))))

(defun find-s (seq str)
  (true (find str seq :test #'string=)))

(defun null-diff (set1 set2)
  (null (set-exclusive-or set1 set2 :test #'equal)))

(defmacro with-test-db (&body body)
  `(with-connection ()
     (cumulative-and
      (check true (red-ping))
      (check true (red-select 15))
      (check true (red-flushdb))
      ,@body
      (check true (red-flushdb)))))

(deftest commands ()
  (with-test-db
    (check true              (red-ping))
    (check true              (red-select 15)) ; select last DB index
    (check true              (red-flushdb))
    #+nil (red-quit)
    #+nil (red-auth)
    (check true              (red-set "y" "1"))
    (check true              (red-set "ігрек" "1"))
    (check string= "1"       (red-getset "y" "2"))
    (check string= "1"       (red-getset "ігрек" "2"))
    (check string= "2"       (red-get "y"))
    (check string= "2"       (red-get "ігрек"))
    (check true              (red-set "z" "3"))
    (check true              (red-set "зед" "3"))
    (check equal '("2" "3")  (red-mget "y" "z"))
    (check equal '("2" "3")  (red-mget "ігрек" "зед"))
    (check equal '("2" nil)  (red-mget "y" "a"))
    (check equal '("2" nil)  (red-mget "ігрек" "а"))
    (check null              (red-setnx "z" "3"))
    (check null              (red-setnx "зед" "3"))
    (check true              (red-setnx "u" "3"))
    (check true              (red-setnx "ю" "3"))
    (check = 4               (red-incr "u"))
    (check = 4               (red-incr "ю"))
    (check = 6               (red-incrby "u" 2))
    (check = 6               (red-incrby "ю" 2))
    (check = 5               (red-decr "u"))
    (check = 5               (red-decr "ю"))
    (check = 3               (red-decrby "u" 2))
    (check = 3               (red-decrby "ю" 2))
    (check true              (red-exists "u"))
    (check true              (red-exists "ю"))
    (check null              (red-exists "v"))
    (check null              (red-exists "ві"))
    (check true              (red-del "u"))
    (check true              (red-del "ю"))
    (check null              (red-exists "u"))
    (check null              (red-exists "ю"))
    (check string= "none"    (red-type "u"))
    (check string= "none"    (red-type "ю"))
    (check string= "string"  (red-type "z"))
    (check string= "string"  (red-type "зед"))
    (check null-diff '("y" "ігрек" "z" "зед")
                             (red-keys "*"))
    (check string= "OK"      (red-rename "z" "c"))
    (check string= "OK"      (red-rename "зед" "це"))
    (check-errs              (red-rename "z" "d"))
    (check string= "3"       (red-get "c"))
    (check string= "3"       (red-get "це"))
    (check null              (red-renamenx "y" "c"))
    (check null              (red-renamenx "ігрек" "це"))
    (check true              (red-renamenx "y" "b"))
    (check true              (red-renamenx "ігрек" "бе"))
    (check-errs              (red-renamenx "b" "b"))
    (check-errs              (red-renamenx "бе" "бе"))
    (check = 4               (red-dbsize))
    (check true              (red-expire "b" 1))
    (check true              (red-expire "бе" 1))
    (check null              (progn (sleep 2)
                                    (red-get "b")))
    (check null              (progn (sleep 2)
                                    (red-get "бе")))
    (check null              (red-expire "b" 1))
    (check null              (red-expire "бе" 1))
    (check find-s '("c" "це")
                             (red-randomkey))
    (check true              (red-expire "c" 600))
    (check true              (red-expire "це" 600))
    (check < 595             (red-ttl "c"))
    (check < 595             (red-ttl "це"))
    (check true              (red-mset "k1" "v1" "k2" "v2"))
    (check true              (red-mset "ка1" "ве1" "ка2" "ве2"))
    (check null              (red-msetnx "k1" "w1" "k3" "v3"))
    (check null              (red-msetnx "ка1" "дубльве1" "ка3" "ве3"))
    (check null              (red-exists "k3"))
    (check null              (red-exists "ка3"))
    (check true              (red-msetnx "k4" "v4" "k5" "v5"))
    (check true              (red-msetnx "ка4" "ве4" "ка5" "ве5"))
    (check equal '("v1" "v2" "v4" "v5")
                             (red-mget "k1" "k2" "k4" "k5"))
    (check equal '("ве1" "ве2" "ве4" "ве5")
                             (red-mget "ка1" "ка2" "ка4" "ка5"))
    (check true              (red-mset "k1" "w1" "k2" "v2"))
    (check true              (red-mset "ка1" "дубльве1" "ка2" "ве2"))
    (check equal "w1"        (red-get "k1"))
    (check equal "дубльве1"  (red-get "ка1"))
    #+nil (red-move)
    #+nil (red-flushall)
    (check true              (red-save))
    (check true              (red-bgsave))
    (check integerp          (red-lastsave))
    #+nil (red-shutdown)
    #+nil (red-info)
    #+nil (red-monitor)
    #+nil (red-slaveof)))

(deftest red-append ()
  ;; from http://code.google.com/p/redis/wiki/AppendCommand
  (with-test-db
    (check null  (red-exists "mykey"))
    (check = 6   (red-append "mykey" "Hello "))
    (check = 11  (red-append "mykey" "World"))
    (check string= "Hello World" (red-get "mykey"))))

(deftest red-substr ()
  ;; from http://code.google.com/p/redis/wiki/SubstrCommand
  (with-test-db
    (check string= "OK"                (red-set "s" "This is a string"))
    (check string= "This"              (red-substr "s" 0 3))
    (check string= "ing"               (red-substr "s" -3 -1))
    (check string= "This is a string"  (red-substr "s" 0 -1))
    (check string= " string"           (red-substr "s" 9 100000))))

(deftest l-commands ()
  (with-test-db
    (check = 1               (red-rpush "l" "1"))
    (check = 1               (red-rpush "эл" "1"))
    (check = 2               (red-rpush "l" "1"))
    (check = 2               (red-rpush "эл" "1"))
    (check = 3               (red-rpush "l" "1"))
    (check = 3               (red-rpush "эл" "1"))
    (check = 3               (red-lrem "l" 0 "1"))
    (check = 3               (red-lrem "эл" 0 "1"))
    (check = 0               (red-lrem "l" 0 "a"))
    (check = 0               (red-lrem "эл" 0 "а"))
    (check true              (red-lpush "l" "1"))
    (check true              (red-lpush "эл" "1"))
    (check true              (red-lpush "l" "0"))
    (check true              (red-lpush "эл" "0"))
    (check = 2               (red-llen "l"))
    (check = 2               (red-llen "эл"))
    (check equal '("0")      (red-lrange "l" 0 0))
    (check equal '("0")      (red-lrange "эл" 0 0))
    (check equal '("0" "1")  (red-lrange "l" 0 -1))
    (check equal '("0" "1")  (red-lrange "l" 0 2))
    (check equal '("0" "1")  (red-lrange "l" 0 10))
    (check null              (red-lrange "l" 2 1))
    (check null              (red-lrange "l" 2 3))
    (check string= "0"       (red-lindex "l" 0))
    (check string= "0"       (red-lindex "эл" 0))
    (check true              (red-lset "l" 0 "a"))
    (check true              (red-lset "эл" 0 "а"))
    (check equal '("a" "1")  (red-lrange "l" 0 10))
    (check equal '("а" "1")  (red-lrange "эл" 0 10))
    (check true              (red-ltrim "l" 0 0))
    (check true              (red-ltrim "эл" 0 0))
    (check equal '("a")      (red-lrange "l" 0 10))
    (check equal '("а")      (red-lrange "эл" 0 10))
    (check true              (red-ltrim "l" 2 3))
    (check true              (red-ltrim "эл" 2 3))
    (check null              (red-lrange "l" 0 10))
    (check null              (red-lrange "эл" 0 10))
    (check true              (red-lpush "l" "2"))
    (check true              (red-lpush "эл" "2"))
    (check true              (red-rpush "l" "3"))
    (check true              (red-rpush "эл" "3"))
    (check true              (red-rpush "l" "4"))
    (check true              (red-rpush "эл" "4"))
    (check true              (red-rpush "эл" "5"))
    (check true              (red-rpush "эл" "6"))
    (check string= "2"       (red-lpop "l"))
    (check string= "2"       (red-lpop "эл"))
    (check string= "4"       (red-rpop "l"))
    (check string= "3"       (red-rpop "l"))
    (check string= "6"       (red-rpop "эл"))
    (check null              (red-blpop "l" 1))
    (check true              (red-rpush "l" "5"))
    (check equal '("l" "5")  (red-blpop "l" 1))
    (check equal '("эл" "3") (red-blpop "эл" 1))
    (check true              (red-rpush "l" "0"))
    (check true              (red-rpush "l" "1"))
    (check true              (red-rpush "l" "2"))
    (check equal '("0" "1" "2")
                             (red-lrange "l" 0 -1))
    (check string= "4"       (red-lpop "эл"))
    (check string= "5"       (red-lpop "эл"))
    (check null              (red-lrange "эл" 0 -1))
    (check string= "2"       (red-rpoplpush "l" "эл"))
    (check string= "1"       (red-rpoplpush "l" "l"))
    (check equal '("2")      (red-lrange "эл" 0 1))
    (check equal '("1" "0")  (red-lrange "l" 0 2))
    (check-errs              (red-get "l"))
    (check-errs              (red-get "эл"))))

(deftest s-commands ()
  (with-test-db
    (check true              (red-sadd "s" "1"))
    (check true              (red-sadd "э" "1"))
    (check null              (red-sadd "s" "1"))
    (check null              (red-sadd "э" "1"))
    (check true              (red-sadd "s" "2"))
    (check true              (red-sadd "э" "2"))
    (check find-s '("2" "1") (red-srandmember "s"))
    (check find-s '("2" "1") (red-spop "s"))
    (check find-s '("2" "1") (red-spop "э"))
    (check true              (or (red-sadd "s" "2")
                                 (red-sadd "s" "1")))
    (check true              (or (red-sadd "э" "2")
                                 (red-sadd "э" "1")))
    (check true              (red-srem "s" "1"))
    (check true              (red-srem "э" "1"))
    (check string= "2"       (red-spop "s"))
    (check string= "2"       (red-spop "э"))
    (check null              (red-spop "s"))
    (check null              (red-spop "э"))
    (check true              (red-sadd "s" "2"))
    (check true              (red-sadd "э" "2"))
    (check true              (red-sismember "s" "2"))
    (check true              (red-sismember "э" "2"))
    (check true              (red-sadd "s" "1"))
    (check true              (red-sadd "э" "1"))
    (check true              (red-smove "s" "s2" "1"))
    (check true              (red-smove "э" "э2" "1"))
    (check true              (red-sismember "s2" "1"))
    (check true              (red-sismember "э2" "1"))
    (check null              (red-smove "s" "s2" "3"))
    (check null              (red-smove "э" "э2" "3"))
    (check null              (red-sismember "s2" "3"))
    (check null              (red-sismember "э2" "3"))
    (check true              (red-sadd "s" "1"))
    (check true              (red-sadd "э" "1"))
    (check true              (red-smove "s" "s2" "1"))
    (check true              (red-smove "э" "э2" "1"))
    (check = 1               (red-scard "s"))
    (check = 1               (red-scard "э"))
    (check null              (red-sinter "s" "s2"))
    (check null              (red-sinter "э" "э2"))
    (check true              (red-sadd "s" "1"))
    (check true              (red-sadd "э" "1"))
    (check equal '("1")      (red-sinter "s" "s2"))
    (check equal '("1")      (red-sinter "э" "э2"))
    (check true              (red-sinterstore "s3" "s" "s2"))
    (check true              (red-sinterstore "э3" "э" "э2"))
    (check equal '("1")      (red-smembers "s3"))
    (check equal '("1")      (red-smembers "э3"))
    (check null-diff '("1" "2")
                             (red-sunion "s" "s2"))
    (check null-diff '("1" "2")
                             (red-sunion "э" "э2"))
    (check true              (red-sunionstore "s4" "s" "s2"))
    (check true              (red-sunionstore "э4" "э" "э2"))
    (check null-diff '("1" "2")
                             (red-smembers "s4"))
    (check equal '("1" "2")  (red-smembers "э4"))
    (check equal '("2")      (red-sdiff "s4" "s3"))
    (check equal '("2")      (red-sdiff "э4" "э3"))
    (check true              (red-sdiffstore "s5" "s4" "s3"))
    (check true              (red-sdiffstore "э5" "э4" "э3"))
    (check equal '("2")      (red-smembers "s5"))
    (check equal '("2")      (red-smembers "э5"))))

(deftest z-commands ()
  (with-test-db
    (check true                (red-zadd "set" 1 "e1"))
    (check true                (red-zadd "множина" 1 "елемент1"))
    (check true                (red-zadd "set" 2 "e2"))
    (check true                (red-zadd "множина" 2 "елемент2"))
    (check true                (red-zadd "set" 3 "e3"))
    (check true                (red-zadd "множина" 3 "елемент3"))
    (check true                (red-zrem "set" "e2"))
    (check true                (red-zrem "множина" "елемент2"))
    (check null                (red-zrem "set" "e2"))
    (check null                (red-zrem "множина" "елемент2"))
    (check true                (red-zadd "set" 10 "e2"))
    (check true                (red-zadd "множина" 10 "елемент2"))
    (check true                (red-zadd "set" 4 "e4"))
    (check true                (red-zadd "множина" 4 "елемент4"))
    (check true                (red-zadd "set" 5 "e5"))
    (check true                (red-zadd "множина" 5 "елемент5"))
    (check = 5                 (red-zcard "set"))
    (check = 10.0              (red-zscore "set" "e2"))
    (check = 4                 (red-zrank "set" "e2"))
    (check = 0                 (red-zrevrank "set" "e2"))
    (check equal '("e3" "e4" "e5")
                               (red-zrange "set" 1 3))
    (check equal '("елемент3" "елемент4" "елемент5")
                               (red-zrange "множина" 1 3))
    (check equal '("e4" "e3" "e1")
                               (red-zrevrange "set" 2 4))
    (check equal '("елемент4" "елемент3" "елемент1")
                               (red-zrevrange "множина" 2 4))
    (check equal '("e5" "e2")  (red-zrangebyscore "set" 5 10))
    (check equal '("елемент5" "елемент2")
                               (red-zrangebyscore "множина" 5 10))
    (check = 3                 (red-zremrangebyscore "set" 2 7))
    (check = 3                 (red-zremrangebyrank "множина" 0 2))
    (check equal '("e1" "e2")  (red-zrange "set" 0 -1))
    (check equal '("елемент5" "елемент2")
                               (red-zrange "множина" 0 -1))
    (check = 4                 (red-zunionstore "s1" 2 '("set" "множина")))
    (check = 0                 (red-zinterstore "s2" 2 '("set" "множина")
                                                :weights '(1 2)
                                                :aggregate :min))
    (check = 2                 (red-zinterstore "s3" 2 '("set" "s1")
                                                :aggregate :sum))))

(deftest h-commands ()
  (with-test-db
    (check = 1               (red-hset "h1" "f1" "a"))
    (check = 1               (red-hset "h1" "f2" "b"))
    (check = 0               (red-hset "h1" "f1" "c"))
    (check string= "c"       (red-hget "h1" "f1"))
    (check equal '("c" "b")  (red-hmget "h1" "f1" "f2"))
    (check string= "OK"      (red-hmset "h1" "f1" "1" "f2" "2"))
    (check = 3               (red-hincrby "h1" "f2" "1"))
    (check = 0               (red-hincrby "h1" "f1" "-1"))
    (check true              (red-hexists "h1" "f1"))
    (check null              (red-hexists "h1" "f3"))
    (check true              (red-hdel "h1" "f1"))
    (check null              (red-hdel "h1" "f3"))
    (check = 1               (red-hlen "h1"))
    (check equal '("f2")     (red-hkeys "h1"))
    (check equal '("3")      (red-hvals "h1"))
    (check equal '("f2" "3") (red-hgetall "h1"))))

(deftest sort()
  (with-test-db
    (check true                    (red-rpush "numbers" "1"))
    (check true                    (red-rpush "числа" "1"))
    (check true                    (red-rpush "numbers" "2"))
    (check true                    (red-rpush "числа" "2"))
    (check true                    (red-rpush "numbers" "3"))
    (check true                    (red-rpush "числа" "3"))
    (check true                    (red-set "object_1" "o1"))
    (check true                    (red-set "об'єкт_1" "о1"))
    (check true                    (red-set "object_2" "o2"))
    (check true                    (red-set "об'єкт_2" "о2"))
    (check true                    (red-set "object_3" "o3"))
    (check true                    (red-set "об'єкт_3" "о3"))
    (check true                    (red-set "weight_1" "47"))
    (check true                    (red-set "вага_1" "47"))
    (check true                    (red-set "weight_2" "13"))
    (check true                    (red-set "вага_2" "13"))
    (check true                    (red-set "weight_3" "32"))
    (check true                    (red-set "вага_3" "32"))
    (check equal '("1" "2" "3")    (red-sort "numbers"))
    (check equal '("1" "2" "3")    (red-sort "числа"))
    (check equal '("2" "3")        (red-sort "numbers" :start 1 :end 2))
    (check equal '("2" "3")        (red-sort "числа" :start 1 :end 2))
    (check equal '("3" "2" "1")    (red-sort "numbers" :desc t))
    (check equal '("2" "1")        (red-sort "numbers" :desc t :start 1 :end 2))
    (check equal '("3" "2" "1")    (red-sort "числа" :desc t))
    (check equal '("2" "1")        (red-sort "числа" :desc t :start 1 :end 2))
    (check equal '("2" "3" "1")    (red-sort "numbers" :by "weight_*"))
    (check equal '("2" "3" "1")    (red-sort "числа" :by "вага_*"))
    (check equal '("o2" "o3" "o1") (red-sort "numbers" :by "weight_*"
                                             :get "object_*"))
    (check equal '("о2" "о3" "о1") (red-sort "числа" :by "вага_*"
                                             :get "об'єкт_*"))
    (check equal '("o1" "o3" "o2") (red-sort "numbers" :by "weight_*"
                                             :get "object_*" :desc t))
    (check equal '("о1" "о3" "о2") (red-sort "числа" :by "вага_*"
                                             :get "об'єкт_*" :desc t))))
(deftest transactions ()
  ;; from http://code.google.com/p/redis/wiki/MultiExecCommand
  (with-test-db
    (check string= "OK"          (red-multi))
    (check string= "QUEUED"      (red-incr "foo"))
    (check string= "QUEUED"      (red-incr "bar"))
    (check string= "QUEUED"      (red-incr "bar"))
    (check equal '("1" "1" "2")  (red-exec))

    (check string= "OK"          (red-multi))
    (check string= "QUEUED"      (red-set "a" "abc"))
    (check string= "QUEUED"      (red-lpop "a"))
    (check-errs                  (red-exec))

    (check true                  (red-set "foo" "1"))
    (check string= "OK"          (red-multi))
    (check string= "QUEUED"      (red-incr "foo"))
    (check string= "OK"          (red-discard))
    (check string= "1"           (red-get "foo"))))

(deftest pubsub ()
  ;; from http://code.google.com/p/redis/wiki/PublishSubscribe
  (with-connection ()
    (cumulative-and
     (check equal '(("subscribe" "foo" "1") ("subscribe" "bar" "2"))
                                 (red-subscribe "foo" "bar"))
     (check equal '("message" "foo" "test")
                                 (progn
                                   (bt:make-thread (lambda ()
                                                     (let ((*echo-p* nil))
                                                       (sleep 1)
                                                       (with-connection ()
                                                         (red-publish "foo"
                                                                      "test")))))
                                   (expect :multi)))
     (check equal '(("unsubscribe" "bar" "1"))
                                 (red-unsubscribe "bar"))
     (check equal '(("unsubscribe" "foo" "0"))
                                 (red-unsubscribe))
     (check equal '(("psubscribe" "news.*" "1"))
                                 (red-psubscribe "news.*"))
     (check equal '("pmessage" "news.*" "news.1" "puf")
                                 (progn
                                   (bt:make-thread (lambda ()
                                                     (let ((*echo-p* nil))
                                                       (sleep 1)
                                                       (with-connection ()
                                                         (red-publish "news.1"
                                                                      "puf")))))
                                   (expect :multi)))
     (check equal '(("punsubscribe" "news.*" "0"))
                                 (red-punsubscribe))
     (check = 0                  (red-publish "test" "test")))))

(deftest pipelining ()
  (with-connection ()
    (red-select 15)
    (red-flushdb)
    (cumulative-and
     (check equal '("PONG" 0) (with-pipelining
                                (red-ping)
                                (red-dbsize)))
     (check-errs (with-pipelining
                   (red-select 2))))))

(defun run-tests (&key echo-p)
  (let ((*echo-p* echo-p))
    (terpri)
    (princ "Runnning CL-REDIS tests... ")
    (princ (if (every (lambda (rez)
                        (and-it (mklist rez)
                                (every (lambda (rez) (eq t rez))
                                       it)))
                      (run-test tell
                                expect
                                commands
                                red-append
                                red-substr
                                l-commands
                                s-commands
                                z-commands
                                h-commands
                                sort
                                transactions
                                pubsub
                                pipelining))
               "OK"
               (format nil "some tests failed. See log file for details: ~a"
                       *log-out*)))
    (terpri)
    (terpri)
    (values)))


;;; end