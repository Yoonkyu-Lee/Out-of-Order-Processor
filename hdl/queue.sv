module queue
#(
    parameter WIDTH = 32,
    parameter DEPTH = 8
)(
    input   logic               clk,
    input   logic               rst,           

    //deqeue
    input   logic               pop,
    output  logic [WIDTH-1:0]   dout,
    output  logic               empty,

    //enqueue
    input   logic               push,
    output  logic               full,
    input   logic [WIDTH-1:0]   din
);


//data
logic [DEPTH-1:0][WIDTH-1:0] queue;


//head and tail pointers
logic [$clog2(DEPTH):0] head, tail;
 

//logic signals
always_comb begin
    //empty - default values
    empty = 1'b0;
    full = 1'b0;
    
    //empty when head equals tail
    if(head == tail) begin
        empty = 1'b1;
    end
    //full
    if(head[$clog2(DEPTH)-1:0] == tail[$clog2(DEPTH)-1:0] &&
       head[$clog2(DEPTH)] != tail[$clog2(DEPTH)]) begin
        full = 1'b1;
    end
end

//dequeue
assign dout = queue[head[$clog2(DEPTH)-1:0]];

always_ff @(posedge clk) begin
    if(rst) begin
        head <= '0;
        tail <= '0;
        queue <= 'x;
    end else begin
        //enqeue
        if(push && !full) begin
            queue[tail[$clog2(DEPTH)-1:0]] <= din;
            tail <= tail + 1'b1;
        end
        //deqeue
        if(pop && !empty) begin
            queue[head[$clog2(DEPTH)-1:0]] <= 'x;
            head <= head + 1'b1;
        end

    end
end




endmodule : queue
