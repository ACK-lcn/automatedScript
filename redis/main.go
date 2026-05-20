package main

/*
此代码为了给redis提供一下常用的案例参考使用
*/

import (
	"context"
	"fmt"
	"log"
	checkerr "redis/checkErr"
	"time"

	"github.com/redis/go-redis/v9"
)

func stringOps(ctx context.Context, client *redis.Client ){
	key := "name"
	value := "lisi"

	// 可以通过client.Set中的expiration（请参考官方源码）参数，设置过期时间
    // 通过Set方法设置
	err := client.Set(ctx, key, value, 10* time.Second).Err()
	checkerr.CheckError(err)

	// 通过Get方法获取
	v, err := client.Get(ctx, key).Result()
	checkerr.CheckError(err)
	fmt.Println(v)

	// 只有当值存在时才打印，避免打印空值误导
	if v != "" {
		fmt.Printf("String Get Result: %s\n", v)
	}
	 
	// 清理数据
	client.Del(ctx, key)
}

// 一般在redis中，key基本都是一个string，但是对于一个value来说，可以是一个string，也可以是一个list列表容器等。
func listOps(ctx context.Context, client *redis.Client){
	key := "dis"
	values := []interface{}{1, 2, "zhangsan", "big", "city", "China"}

	// 如果value是一个list，则设置redis时，不能使用Set， 需要使用RPush 左侧插入.
	err := client.LPush(ctx, key, values...).Err()
	checkerr.CheckError(err)

	// 如果valu是一个list，则获取redis时，不能使用Get，需要使用LRange.
	v2, err := client.LRange(ctx, key, 0, -1).Result()
	checkerr.CheckError(err)
	fmt.Println(v2)

	// 清理数据
	client.Del(ctx, key)
}

// hash 操作示例
func hashOps(ctx context.Context, client *redis.Client){
	key := "hs"
	values := map[string]interface{}{
		"name": "王五",
		"age": 26,
		"city": "上海",
		"country": "China",
	}

	// 通过HSet设置
	err := client.HSet(ctx, key, values).Err()
	checkerr.CheckError(err)

	// 方法一：通过HGet获取
	rs, err := client.HGet(ctx, key, "name").Result()
	checkerr.CheckError(err)
	fmt.Println(rs)

	// 方法二：通过HGetAll获取所有
	cm := client.HGetAll(ctx, key)
	if err := cm.Err(); err != nil {
		checkerr.CheckError(err)
	}

	fmt.Println("Hash All Fields:")

	// 通过for range遍历获取
	for fields, value := range cm.Val() {
		fmt.Printf("  %s:  %s\n", fields, value)
	}

	// 清理数据
	client.Del(ctx, key)
}

func main(){
	// 创建带有超时控制的Context， 防止Redis 操作无限阻塞
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client := redis.NewClient(&redis.Options{
		Addr: "127.0.0.1:6379",
		Password: "",
		DB: 0,
		PoolSize: 15, // 连接池大小，请根据实际需求调整
		ReadTimeout: 6 * time.Second,
		WriteTimeout: 2 * time.Second,
	})

	// 程序退出时关闭连接
	defer client.Close()

	// 测试连接是否成功，可以通过Ping测试，可选选项
	if err := client.Ping(ctx).Err(); err != nil {
		log.Fatalf("Redis数据库连接失败: %v", err)
	}

	fmt.Println("Redis数据库连接成功.")

	 stringOps(ctx, client)
	 listOps(ctx, client)
	 hashOps(ctx, client)
}