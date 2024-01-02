# caddy-xtls-docker
用docker-compose部署xray-vless-xtls服务端
# 用法
预留80、443、8081、8082端口
然后
```
mkdir caddy-xtls && cd caddy-xtls
curl -LO https://raw.githubusercontent.com/starP-W/caddy-xtls-docker/main/install.py && python3 install.py -o install
```
```
-o install/update/remove
-l --local 从本地Dockerfile编译caddy镜像，非x64架构可尝试使用
-a 删除时一并删除镜像
```