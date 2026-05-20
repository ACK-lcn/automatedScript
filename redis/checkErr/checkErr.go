package checkerr

import (
	"log"

	"github.com/redis/go-redis/v9"
)

func CheckError(err error) {
	if err != nil {
		if err == redis.Nil {
			return
		} 
		log.Printf("Redis operation error: %v", err)
	}
}

func MustCheckError(err error) {
	if err != nil && err != redis.Nil {
		log.Fatalf("Fatal Redis error: %v", err)
	}
}