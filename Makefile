include /home/isucon/env.sh

# 変数定義 ------------------------

# SERVER_ID: env.sh内で定義

USER:=isucon
BUILD_DIR:=/home/isucon/webapp/go
SERVICE_NAME:=isucholar.go.service
BIN_NAME:=isucholar

DB_PATH:=/etc/mysql
NGINX_PATH:=/etc/nginx
SYSTEMD_PATH:=/etc/systemd/system

NGINX_LOG:=/var/log/nginx/access.log
DB_SLOW_LOG:=/var/log/mysql/mysql-slow.log

REPOSITORY_NAME:=play_isucon11

# メインで使うコマンド ------------------------

# サーバーの環境構築　ツールのインストール、gitまわりのセットアップ
.PHONY: setup
setup: install-tools

# 設定ファイルなどを取得してgit管理下に配置する
.PHONY: get
get: check-server-id get-db-conf get-nginx-conf get-service-file get-envsh get-src get-sql

# リポジトリ内の設定ファイルをそれぞれ配置する
.PHONY: deploy
deploy: check-server-id deploy-db-conf deploy-nginx-conf deploy-envsh deploy-src deploy-sql

# ベンチマークを走らせる直前に実行する
.PHONY: bench
bench: check-server-id mv-logs deploy build restart watch-service-log

# pprofで記録する
.PHONY: pprof-record
pprof-record:
	go tool pprof -http=0.0.0.0:1080 /home/isucon/webapp/go/isucholar http://localhost:6060/debug/pprof/profile

# pprofで確認する
.PHONY: pprof-check
pprof-check:
	$(eval latest := $(shell ls -rt pprof/ | tail -n 1))
	go tool pprof -http=localhost:8090 pprof/$(latest)

# DBに接続する
.PHONY: access-db
access-db:
	mysql -h $(MYSQL_DB_HOST) -P $(MYSQL_DB_PORT) -u $(MYSQL_DB_user) -p$(MYSQL_DB_PASSWORD) $(MYSQL_DB_NAME)

# 主要コマンドの構成要素 ------------------------

.PHONY: install-tools
install-tools:
	# slow query log取得用のコマンド
	sudo apt update
	sudo apt upgrade
	sudo apt install -y percona-toolkit dstat git unzip graphviz tree

	# alpのインストール
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.15/alp_linux_amd64.zip
	unzip alp_linux_amd64.zip
	sudo install alp /usr/local/bin/alp
	rm alp_linux_amd64.zip alp

.PHONY: git-setup
git-setup:
	# git用の設定は適宜変更して良い
	git config --global user.email "example@gmail.com"
	git config --global user.name "example"

	# deploykeyの作成
	ssh-keygen -t ed25519

.PHONY: check-server-id
check-server-id:
ifdef SERVER_ID
	@echo "SERVER_ID=$(SERVER_ID)"
else
	@echo "SERVER_ID is unset"
	@exit 1
endif

.PHONY: set-as-s1
set-as-s1:
	echo "SERVER_ID=s1" >> /home/isucon/env.sh

.PHONY: set-as-s2
set-as-s2:
	echo "SERVER_ID=s2" >> /home/isucon/env.sh

.PHONY: set-as-s3
set-as-s3:
	echo "SERVER_ID=s3" >> /home/isucon/env.sh

.PHONY: get-db-conf
get-db-conf:
	sudo cp -R $(DB_PATH)/* ~/$(REPOSITORY_NAME)/$(SERVER_ID)/etc/mysql
	sudo chown $(USER) -R ~/$(REPOSITORY_NAME)/$(SERVER_ID)/etc/mysql

.PHONY: get-nginx-conf
get-nginx-conf:
	sudo cp -R $(NGINX_PATH)/* ~/$(REPOSITORY_NAME)/$(SERVER_ID)/etc/nginx
	sudo chown $(USER) -R ~/$(REPOSITORY_NAME)/$(SERVER_ID)/etc/nginx

.PHONY: get-service-file
get-service-file:
	sudo cp $(SYSTEMD_PATH)/$(SERVICE_NAME) ~/$(REPOSITORY_NAME)/$(SERVER_ID)/etc/systemd/system/
	sudo chown $(USER) ~/$(REPOSITORY_NAME)/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)

.PHONY: get-envsh
get-envsh:
	cp ~/env.sh ~/$(REPOSITORY_NAME)/$(SERVER_ID)/home/isucon/

.PHONY: get-go-src
get-src:
	cp -R /home/isucon/webapp/go/main.go ~/$(REPOSITORY_NAME)/$(SERVER_ID)/home/isucon/webapp/go/
	cp -R /home/isucon/webapp/go/go.mod ~/$(REPOSITORY_NAME)/$(SERVER_ID)/home/isucon/webapp/go/
	cp -R /home/isucon/webapp/go/go.sum ~/$(REPOSITORY_NAME)/$(SERVER_ID)/home/isucon/webapp/go/
	cp -R /home/isucon/webapp/go/db.go ~/$(REPOSITORY_NAME)/$(SERVER_ID)/home/isucon/webapp/go/
	cp -R /home/isucon/webapp/go/util.go ~/$(REPOSITORY_NAME)/$(SERVER_ID)/home/isucon/webapp/go/

.PHONY: get-sql
get-sql:
	cp -R ~/webapp/sql/* ~/$(REPOSITORY_NAME)/$(SERVER_ID)/home/isucon/webapp/sql

.PHONY: deploy-db-conf
deploy-db-conf:
	sudo cp -R ~/$(REPOSITORY_NAME)/$(SERVER_ID)/etc/mysql/* $(DB_PATH)

.PHONY: deploy-nginx-conf
deploy-nginx-conf:
	sudo cp -R ~/$(REPOSITORY_NAME)/$(SERVER_ID)/etc/nginx/* $(NGINX_PATH)

.PHONY: deploy-service-file
deploy-service-file:
	sudo cp ~/$(REPOSITORY_NAME)/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME) $(SYSTEMD_PATH)/$(SERVICE_NAME)

.PHONY: deploy-envsh
deploy-envsh:
	cp ~/$(REPOSITORY_NAME)/$(SERVER_ID)/home/isucon/env.sh ~/env.sh

.PHONY: deploy-src
deploy-src:
	cp ~/$(REPOSITORY_NAME)/$(SERVER_ID)/home/isucon/webapp/go/* /home/isucon/webapp/go

.PHONY: deploy-sql
deploy-sql:
	cp -R ~/$(REPOSITORY_NAME)/$(SERVER_ID)/home/isucon/webapp/sql/* ~/webapp/sql

.PHONY: build
build:
	cd $(BUILD_DIR); \
	go build -o $(BIN_NAME) -ldflags="-s -w"

# ec2に合わせて修正する
.PHONY: restart
restart:
	sudo systemctl daemon-reload
	sudo systemctl restart mysql
	sudo systemctl restart $(SERVICE_NAME)
	sudo systemctl restart nginx

.PHONY: mv-logs
mv-logs:
	$(eval when := $(shell date "+%s"))
	mkdir -p ~/logs/nginx/$(when)
	mkdir -p ~/logs/mysql/$(when)
	sudo test -f $(NGINX_LOG) && \
		sudo mv -f $(NGINX_LOG) ~/logs/nginx/$(when)/
	sudo test -f $(DB_SLOW_LOG) && \
		sudo mv -f $(DB_SLOW_LOG) ~/logs/mysql/$(when)/

.PHONY: watch-service-log
watch-service-log:
	sudo journalctl -u $(SERVICE_NAME) -n10 -f
