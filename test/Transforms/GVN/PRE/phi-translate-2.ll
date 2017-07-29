; RUN: opt < %s -gvn -S | FileCheck %s
target datalayout = "e-m:e-i64:64-f80:128-n8:16:32:64-S128"

@a = common global [100 x i64] zeroinitializer, align 16
@b = common global [100 x i64] zeroinitializer, align 16
@g1 = common global i64 0, align 8
@g2 = common global i64 0, align 8
@g3 = common global i64 0, align 8
declare i64 @goo(...) local_unnamed_addr #1

define void @test1(i64 %a, i64 %b, i64 %c, i64 %d) {
entry:
  %mul = mul nsw i64 %b, %a
  store i64 %mul, i64* @g1, align 8
  %t0 = load i64, i64* @g2, align 8
  %cmp = icmp sgt i64 %t0, 3
  br i1 %cmp, label %if.then, label %if.end

if.then:                                          ; preds = %entry
  %mul2 = mul nsw i64 %d, %c
  store i64 %mul2, i64* @g2, align 8
  br label %if.end

; Check phi-translate works and mul is removed.
; CHECK-LABEL: @test1(
; CHECK: if.end:
; CHECK: %[[MULPHI:.*]] = phi i64 [ {{.*}}, %if.then ], [ %mul, %entry ]
; CHECK-NOT: = mul
; CHECK: store i64 %[[MULPHI]], i64* @g3, align 8
if.end:                                           ; preds = %if.then, %entry
  %b.addr.0 = phi i64 [ %d, %if.then ], [ %b, %entry ]
  %a.addr.0 = phi i64 [ %c, %if.then ], [ %a, %entry ]
  %mul3 = mul nsw i64 %a.addr.0, %b.addr.0
  store i64 %mul3, i64* @g3, align 8
  ret void
}

define void @test2(i64 %i) {
entry:
  %arrayidx = getelementptr inbounds [100 x i64], [100 x i64]* @a, i64 0, i64 %i
  %t0 = load i64, i64* %arrayidx, align 8
  %arrayidx1 = getelementptr inbounds [100 x i64], [100 x i64]* @b, i64 0, i64 %i
  %t1 = load i64, i64* %arrayidx1, align 8
  %mul = mul nsw i64 %t1, %t0
  store i64 %mul, i64* @g1, align 8
  %cmp = icmp sgt i64 %mul, 3
  br i1 %cmp, label %if.then, label %if.end

; Check phi-translate works for the phi generated by loadpre. A new mul will be
; inserted in if.then block.
; CHECK-LABEL: @test2(
; CHECK: if.then:
; CHECK: %[[MUL_THEN:.*]] = mul
; CHECK: br label %if.end
if.then:                                          ; preds = %entry
  %call = tail call i64 (...) @goo() #2
  store i64 %call, i64* @g2, align 8
  br label %if.end

; CHECK: if.end:
; CHECK: %[[MULPHI:.*]] = phi i64 [ %[[MUL_THEN]], %if.then ], [ %mul, %entry ]
; CHECK-NOT: = mul
; CHECK: store i64 %[[MULPHI]], i64* @g3, align 8
if.end:                                           ; preds = %if.then, %entry
  %i.addr.0 = phi i64 [ 3, %if.then ], [ %i, %entry ]
  %arrayidx3 = getelementptr inbounds [100 x i64], [100 x i64]* @a, i64 0, i64 %i.addr.0
  %t2 = load i64, i64* %arrayidx3, align 8
  %arrayidx4 = getelementptr inbounds [100 x i64], [100 x i64]* @b, i64 0, i64 %i.addr.0
  %t3 = load i64, i64* %arrayidx4, align 8
  %mul5 = mul nsw i64 %t3, %t2
  store i64 %mul5, i64* @g3, align 8
  ret void
}

; Check phi-translate doesn't go through backedge, which may lead to incorrect
; pre transformation.
; CHECK: for.end:
; CHECK-NOT: %{{.*pre-phi}} = phi
; CHECK: ret void
define void @test3(i64 %N, i64* nocapture readonly %a) {
entry:
  br label %for.cond

for.cond:                                         ; preds = %for.body, %entry
  %i.0 = phi i64 [ 0, %entry ], [ %add, %for.body ]
  %add = add nuw nsw i64 %i.0, 1
  %arrayidx = getelementptr inbounds i64, i64* %a, i64 %add
  %tmp0 = load i64, i64* %arrayidx, align 8
  %cmp = icmp slt i64 %i.0, %N
  br i1 %cmp, label %for.body, label %for.end

for.body:                                         ; preds = %for.cond
  %call = tail call i64 (...) @goo() #2
  %add1 = sub nsw i64 0, %call
  %tobool = icmp eq i64 %tmp0, %add1
  br i1 %tobool, label %for.cond, label %for.end

for.end:                                          ; preds = %for.body, %for.cond
  %i.0.lcssa = phi i64 [ %i.0, %for.body ], [ %i.0, %for.cond ]
  %arrayidx2 = getelementptr inbounds i64, i64* %a, i64 %i.0.lcssa
  %tmp1 = load i64, i64* %arrayidx2, align 8
  store i64 %tmp1, i64* @g1, align 8
  ret void
}

; It is incorrect to use the value of %andres in last loop iteration
; to do pre.
; CHECK-LABEL: @test4(
; CHECK: for.body:
; CHECK-NOT: %andres.pre-phi = phi i32
; CHECK: br i1 %tobool1

define i32 @test4(i32 %cond, i32 %SectionAttrs.0231.ph, i32 *%AttrFlag) {
for.body.preheader:
  %t514 = load volatile i32, i32* %AttrFlag
  br label %for.body

for.body:
  %t320 = phi i32 [ %t334, %bb343 ], [ %t514, %for.body.preheader ]
  %andres = and i32 %t320, %SectionAttrs.0231.ph
  %tobool1 = icmp eq i32 %andres, 0
  br i1 %tobool1, label %bb343, label %critedge.loopexit

bb343:
  %t334 = load volatile i32, i32* %AttrFlag
  %tobool2 = icmp eq i32 %cond, 0
  br i1 %tobool2, label %critedge.loopexit, label %for.body

critedge.loopexit:
  unreachable
}
