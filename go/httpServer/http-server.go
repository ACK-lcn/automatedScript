package main

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
)

type Data struct {
	Name string
	Age  int
}

type Ret struct {
	Status string
	Data   string
}

func TestApi(w http.ResponseWriter, req *http.Request) {
	ret := new(Ret)

	ret.Status = "OK"
	ret.Data = "This is yourDir test_api"
	ret_json, _ := json.Marshal(ret)

	io.WriteString(w, string(ret_json))
}

func HelloServer(w http.ResponseWriter, req *http.Request) {
	io.WriteString(w, "hello, world1!\n")
}

func main() {
	http.HandleFunc("/hello", HelloServer)
	http.HandleFunc("/yourDoc/api_test", TestApi)
	err := http.ListenAndServe(":8080", nil)

	if err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
}
