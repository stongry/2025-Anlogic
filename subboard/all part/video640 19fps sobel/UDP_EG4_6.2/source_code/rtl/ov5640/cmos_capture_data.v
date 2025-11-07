//****************************************Copyright (c)***********************************//
//ԭ�Ӹ����߽�ѧƽ̨��www.yuanzige.com
//����֧�֣�www.openedv.com
//�Ա����̣�http://openedv.taobao.com
//��ע΢�Ź���ƽ̨΢�źţ�"����ԭ��"����ѻ�ȡZYNQ & FPGA & STM32 & LINUX���ϡ�
//��Ȩ���У�����ؾ���
//Copyright(C) ����ԭ�� 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           cmos_capture_data
// Last modified Date:  2020/05/04 9:19:08
// Last Version:        V1.0
// Descriptions:       ����ͷ�ɼ�ģ��
//                      
//----------------------------------------------------------------------------------------
// Created by:          ����ԭ��
// Created date:        2019/05/04 9:19:08
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//
module cmos_capture_data(
    input                 rst_n            ,  //��λ�ź�    
    //����ͷ�ӿ�                           
    input                 cam_pclk         ,  //cmos ��������ʱ��
    input                 cam_vsync        ,  //cmos ��ͬ���ź�
    input                 cam_href         ,  //cmos ��ͬ���ź�
    input  [7:0]          cam_data         ,                      
    //�û��ӿ�                              
    output                cmos_frame_vsync ,  //֡��Ч�ź�    
    output                cmos_frame_href  ,  //����Ч�ź�
    output                cmos_frame_valid ,  //������Чʹ���ź�
    output       [15:0]   cmos_frame_data     //��Ч����        
    );

//�Ĵ���ȫ��������ɺ��ȵȴ�10֡����
//���Ĵ���������Ч���ٿ�ʼ�ɼ�ͼ��
parameter  WAIT_FRAME = 4'd10    ;            //等待10帧使传感器稳定            
							     
//reg define                     
reg             cam_vsync_d0     ;
reg             cam_vsync_d1     ;
reg             cam_href_d0      ;
reg             cam_href_d1      ;
reg    [3:0]    cmos_ps_cnt      ;            //�ȴ�֡���ȶ�������
reg    [7:0]    cam_data_d0      ;            
reg    [15:0]   cmos_data_t      ;            //����8λת16λ����ʱ�Ĵ���
reg             byte_flag        ;            //16λRGB����ת����ɵı�־�ź�
reg             byte_flag_d0     ;
reg             frame_val_flag   ;            //֡��Ч�ı�־ 

wire            pos_vsync        ;            //�����볡ͬ���źŵ�������

//*****************************************************
//**                    main code
//*****************************************************

//�����볡ͬ���źŵ�������
assign pos_vsync = (~cam_vsync_d1) & cam_vsync_d0; 

//���֡��Ч�ź�
assign  cmos_frame_vsync = frame_val_flag  ?  cam_vsync_d1  :  1'b0; 

//�������Ч�ź�
assign  cmos_frame_href  = frame_val_flag  ?  cam_href_d1   :  1'b0; 

//�������ʹ����Ч�ź�
assign  cmos_frame_valid = frame_val_flag  ?  byte_flag_d0  :  1'b0; 

//�������
assign  cmos_frame_data  = frame_val_flag  ?  cmos_data_t   :  1'b0; 
       
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) begin
        cam_vsync_d0 <= 1'b0;
        cam_vsync_d1 <= 1'b0;
        cam_href_d0 <= 1'b0;
        cam_href_d1 <= 1'b0;
    end
    else begin
        cam_vsync_d0 <= cam_vsync;
        cam_vsync_d1 <= cam_vsync_d0;
        cam_href_d0 <= cam_href;
        cam_href_d1 <= cam_href_d0;
    end
end

//��֡�����м���
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n)
        cmos_ps_cnt <= 4'd0;
    else if(pos_vsync && (cmos_ps_cnt < WAIT_FRAME))
        cmos_ps_cnt <= cmos_ps_cnt + 4'd1;
end

//֡��Ч��־ - 修复：一旦设置就保持为1
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n)
        frame_val_flag <= 1'b0;
    else if((cmos_ps_cnt == WAIT_FRAME) && pos_vsync)
        frame_val_flag <= 1'b1;
    else;
end            

//8λ����ת16λRGB565����        
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n) begin
        cmos_data_t <= 16'd0;
        cam_data_d0 <= 8'd0;
        byte_flag <= 1'b0;
    end
    else if(cam_href) begin
        byte_flag <= ~byte_flag;
        cam_data_d0 <= cam_data;
        if(byte_flag)
            cmos_data_t <= {cam_data_d0,cam_data};
        else;   
    end
    else begin
        byte_flag <= 1'b0;
        cam_data_d0 <= 8'b0;
    end    
end        

//�������������Ч�ź�(cmos_frame_valid)
always @(posedge cam_pclk or negedge rst_n) begin
    if(!rst_n)
        byte_flag_d0 <= 1'b0;
    else
        byte_flag_d0 <= byte_flag;	
end 
       
endmodule
