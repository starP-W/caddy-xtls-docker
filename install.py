import argparse
import subprocess as sbp
import os
import json

parser = argparse.ArgumentParser(description="manual to thie script")
parser.add_argument("-o", type=str, default="",help="install/update/remove")
parser.add_argument("-a", action="store_true",help="删除时连镜像一并删除")
parser.add_argument("-l","--local",action="store_true",help="在本地编译caddy镜像，会删除所有的builder缓存")
args = parser.parse_args()


def precheck():
    docker_components = ["docker", "docker-compose"]
    is_docker_component_exists = True
    for docker_component in docker_components:
        try:
            sbp.run([docker_component], stdout=sbp.PIPE, stderr=sbp.PIPE)
            is_docker_component_exists = True and is_docker_component_exists
        except FileNotFoundError:
            is_docker_component_exists = False
    if not is_docker_component_exists:
        print("docker环境缺失")
        exit(-1)
    essential_files = [
        "Dockerfile",
        "Caddyfile",
        "config.json",
        "docker-compose.yml",
    ]
    essential_dirs = ["Webdata"]
    if not os.path.exists("docker-config.json"):
        sbp.call(["touch", "docker-config.json"])
        sbp.run("echo \{\} > docker-config.json", shell=True)
    for file in essential_files:
        if not os.path.exists(file):
            sbp.call(
                [
                    "curl",
                    "-sLO",
                    f"https://raw.githubusercontent.com/starP-W/caddy-xtls-docker/main/{file}",
                ]
            )
            # sbp.call(["touch", file])
    for essential_dir in essential_dirs:
        if not os.path.exists(essential_dir):
            sbp.call(["mkdir", "-p", essential_dir])


def install():
    precheck()
    config_dict = {}
    with open("docker-config.json", "r") as f:
        setting_items = json.load(f)

        setting_items["EMAIL"] = to_change_settings(setting_items, "email")
        setting_items["CF_API_TOKEN"] = to_change_settings(
            setting_items, "cf_api_token"
        )
        setting_items["HOST"] = to_change_settings(setting_items, "host")
        setting_items["UUID"] = to_change_settings(setting_items, "uuid")

        web_type = input("站点运行方式？1：静态文件 2：反向代理（默认1）")
        if web_type == "2":
            sbp.call(["sed", "-i", "-E", "23,24s|^|#|", "Caddyfile"])
            sbp.call(["sed", "-i", "-E", "18,21s|#+||", "Caddyfile"])
            rev_proxy = input("反向代理的URL是：")
            sbp.run(f"sed -i -E '19s|to .*|to {rev_proxy}|' Caddyfile", shell=True)
        else:
            sbp.call(["sed", "-i", "-E", "23,24s|#+||", "Caddyfile"])
            sbp.call(["sed", "-i", "-E", "18,21s|^|#|", "Caddyfile"])
        if args.l:
            sbp.run("sed -i -E '4s|#+||' docker-compose.yml",shell=True)
            sbp.run("sed -i -E '5s|^|#|' docker-compose.yml",shell=True)
        else:
            sbp.run("sed -i -E '4s|^|#|' docker-compose.yml",shell=True)
            sbp.run("sed -i -E '5s|#+||' docker-compose.yml",shell=True)


        sbp.call(["docker-compose", "down", "--rmi", "all"])
        if args.l:
            sbp.run("docker-compose build",shell=True)
            sbp.run("docker builder prune -f",shell=True)
        sbp.call(["docker-compose", "up", "-d"])
        config_dict = setting_items

    with open("docker-config.json", "w") as w:
        json.dump(config_dict, w)
        print(
            f'Vless分享链接：vless://{config_dict["UUID"]}@{config_dict["HOST"]}:443?'
            + f'flow=xtls-rprx-vision&encryption=none&security=tls&type=tcp&headerType=none#{str.upper(config_dict["HOST"])}'
        )


def to_change_settings(setting_items, setting_item):
    setting_item_upper = str.upper(setting_item)
    if setting_item_upper not in setting_items:
        return change_settings(str.lower(setting_item), None)
    elif (
        str.lower(
            input(
                f"打算更改 {setting_item}={setting_items[setting_item_upper]} 的配置？（y或n 默认n）"
            )
        )
        == "y"
    ):
        return change_settings(str.lower(setting_item), None)
    else:
        change_settings(setting_item, setting_items[setting_item_upper])
        return setting_items[setting_item_upper]


def change_settings(setting_item, setting_item_content):
    if setting_item == "email":
        email = (
            input("输入用于ZeroSSL的邮箱：")
            if setting_item_content == None
            else setting_item_content
        )
        sbp.call(["sed", "-i", "-E", f"29s|(email ).*|\\1{email}|", "Caddyfile"])
        return email
    elif setting_item == "uuid":
        if not setting_item_content:
            setting_item_content = sbp.run(
                "curl -s https://www.uuidgenerator.net/api/version4",
                shell=True,
                stdout=sbp.PIPE,
                text=True,
            ).stdout
        sbp.call(
            [
                "sed",
                "-i",
                "-E",
                f'12s|"id": ".*",|"id": "{setting_item_content}",|',
                "config.json",
            ]
        )
        return setting_item_content

    elif setting_item == "cf_api_token":
        cf_api_token = (
            input("输入你的Cloudflare API Token：")
            if setting_item_content == None
            else setting_item_content
        )
        sbp.call(
            [
                "sed",
                "-i",
                "-E",
                f"30s|(cloudflare ).*|\\1{cf_api_token}|",
                "Caddyfile",
            ]
        )
        return cf_api_token

    elif setting_item == "host":
        host = (
            input("输入你的域名：") if setting_item_content == None else setting_item_content
        )
        sbp.call(
            [
                "sed",
                "-i",
                "-E",
                f"26s|(https://).*:8082|\\1{host}:8082|",
                "Caddyfile",
            ]
        )
        sbp.call(
            [
                "sed",
                "-i",
                "-E",
                f's|"certificateFile": ".*",|"certificateFile": "/tls/certificates/acme.zerossl.com-v2-dv90/{host}/{host}.crt",|',
                "config.json",
            ]
        )
        sbp.call(
            [
                "sed",
                "-i",
                "-E",
                f's|"keyFile": ".*"|"keyFile": "/tls/certificates/acme.zerossl.com-v2-dv90/{host}/{host}.key"|',
                "config.json",
            ]
        )
        return host


def update():
    # print("update")
    target = input("要更新的镜像是（caddy或xray）：")
    cmd1 = sbp.run(
        f"docker-compose images | grep {target} | awk '{{print $4}}'",
        shell=True,
        stdout=sbp.PIPE,
    )
    if target == "caddy" or target == "xray":
        sbp.call(f"docker-compose rm -sf {target}", shell=True)
        sbp.run(f"docker rmi {cmd1.stdout}", shell=True)
        sbp.run(f"docker-compose up -d {target}", shell=True)


def remove(all):
    # print("remove")
    s = " --rmi all" if not all else ""
    sbp.call(f"docker-compose down{s}", shell=True)


if __name__ == "__main__":
    # print(args.i)
    if args.o == "install":
        install()
    elif args.o == "update":
        update()
    elif args.o == "remove":
        remove(args.a)
    else:
        print("输入-h查看帮助")
